import Foundation
import CoreBluetooth
import CoreLocation
import CoreMotion
import Combine
import WidgetKit
import UIKit

/// BLE RSSI 기반 자동 잠금/해제 서비스
/// Android AutoLockForegroundService를 iOS CoreBluetooth + CoreLocation으로 포팅
///
/// iOS 백그라운드 BLE 제한 안내:
/// - Background Mode: "Uses Bluetooth LE accessories" 활성화 필요
/// - 백그라운드에서는 CBCentralManagerScanOptionAllowDuplicatesKey 무시됨
/// - 연결(connect) 기반이 아닌 스캔(advertising) 기반이므로 백그라운드에서 빈도 제한 있음
/// - CBCentralManagerOptionRestoreIdentifierKey로 상태 복원 지원
@MainActor
final class AutoLockService: NSObject, ObservableObject {

    static let shared = AutoLockService()

    // MARK: - Published State

    @Published var isRunning = false
    @Published var proximityState: ProximityState = .far
    @Published var rawRssi: Int?
    @Published var smoothedRssi: Double?
    @Published var lastApiResult: String?
    @Published var lastApiTime: Date?
    @Published var scanModeDescription = "중지됨"
    @Published var isInsideGeofence = false
    @Published var isStationary = false
    @Published var isDriving = false
    @Published var lastParkingLat: Double = 0
    @Published var lastParkingLng: Double = 0
    @Published var lastParkingTime: Date?

    enum ProximityState: String { case near = "NEAR", far = "FAR" }

    // MARK: - Private

    private var centralManager: CBCentralManager?
    private var vehicleService: BydVehicleService?
    private let storage = StorageManager.shared
    private let geofenceManager = GeofenceManager.shared

    private var isScanning = false
    private var isFirstRssiAfterConnect = false
    private var targetMac: String?
    private var targetName: String?
    private var connectedPeripheral: CBPeripheral?
    private var rssiTimer: DispatchSourceTimer?
    private static let rssiReadInterval: TimeInterval = 3.0

    // RSSI 필터링
    private struct RssiPoint { let time: Date; let dbm: Int }
    private var rssiWindow = [RssiPoint]()
    private var consecutiveRejections = 0
    private static let rssiWindowSize = 10
    private static let maxRejections = 3

    // 자동 lock/unlock 쿨다운 (진동 방지)
    private var lastAutoUnlockTime: Date?
    private var lastAutoLockTime: Date?
    private static let postUnlockLockCooldown: TimeInterval = 30   // unlock 후 lock 차단
    private static let postLockUnlockCooldown: TimeInterval = 30   // lock 후 unlock 차단

    // 반복 동작 과다 방지 (슬라이딩 윈도우)
    private var recentAutoActionTimes = [Date]()
    private static let autoActionWindow: TimeInterval = 120        // 2분 윈도우
    private static let maxAutoActionsInWindow = 4                  // 2분 내 4회 초과 시 차단
    private var autoActionSuppressedUntil: Date?
    private static let suppressDuration: TimeInterval = 300        // 5분 차단

    // 백그라운드 RSSI 폴링 보장용 Background Task
    private var rssiPollingBGTaskID = UIBackgroundTaskIdentifier.invalid
    // BG Task 만료로 인한 BLE 끊김은 신호 소실이 아님을 표시
    private var isIntentionalDisconnect = false

    // 워치독 타이머 (5분)
    private var watchdogTimer: DispatchSourceTimer?
    private static let watchdogInterval: TimeInterval = 300

    // 정지 감지 (5분)
    private var motionManager: CMMotionActivityManager?
    private var stationaryTimer: DispatchSourceTimer?
    private static let stationaryTimeout: TimeInterval = 300

    // 주행 중 감지 (상시)
    private var drivingMotionManager: CMMotionActivityManager?

    // 마지막으로 알려진 차량 잠금 상태 (nil = 모름)
    private var lastKnownLocked: Bool? = nil

    // 신호 소실 grace timer (BLE 끊김 후 즉시 잠금 대신 60초 유예)
    private var signalLossTimer: DispatchSourceTimer?
    private static let signalLossGracePeriod: TimeInterval = 60

    // 예측적 사전 잠금 해제
    private var isPredictiveUnlockPending = false
    private static let predictiveMargin: Double = 8      // 임계값 이전 몇 dBm에서 사전 호출
    private static let predictiveMinSlope: Double = 0.5  // 최소 상승 기울기 (dBm/초)


    // 세션 갱신 타이머 (15분)
    private var sessionRefreshTimer: DispatchSourceTimer?
    private static let sessionRefreshInterval: TimeInterval = 900

    // GPS 폴링 (5분 주기)
    private var gpsPollTimer: DispatchSourceTimer?
    private static let gpsPollInterval: TimeInterval = 300

    private override init() {
        super.init()
        geofenceManager.delegate = self
    }

    // MARK: - Public API

    func start() {
        guard storage.isServiceEnabled,
              let mac = storage.deviceMac, !mac.isEmpty else { return }
        targetMac  = mac
        targetName = storage.deviceName

        do {
            vehicleService = try BydVehicleService(config: BydConfig.fromRegion(storage.region))
            Task {
                await vehicleService?.setCredentials(username: storage.username ?? "", password: storage.password ?? "")
                if let u = storage.userId, let s = storage.signToken, let e = storage.encryToken {
                    await vehicleService?.restoreSession(userId: u, signToken: s, encryToken: e)
                }
                await setupSessionCallbacks()
            }
        } catch {
            LogManager.shared.log("AutoLockService", "BydVehicleService 초기화 실패: \(error)")
            return
        }

        // 저장된 마지막 위치 복원
        lastParkingLat = storage.lastVehicleLat
        lastParkingLng = storage.lastVehicleLng
        if storage.lastVehicleTime > 0 {
            lastParkingTime = Date(timeIntervalSince1970: storage.lastVehicleTime)
        }

        isRunning = true
        startBLEScan()
        startWatchdog()
        startSessionRefresh()
        startGpsPoll()
        startDrivingDetection()
        storage.saveWidgetData(isRunning: true, isLocked: nil, battery: nil, drivingRange: nil)
        WatchConnectivityManager.shared.sendStatusToWatch(isRunning: true, isLocked: nil, battery: nil, rssi: nil)
        WidgetCenter.shared.reloadAllTimelines()

        // 백그라운드 실행 유지: startUpdatingLocation으로 앱 suspend 차단
        // (10m 정확도, GPS 사용 - 배터리 소모 있으나 안정적인 백그라운드 동작 보장)
        geofenceManager.setup()
        geofenceManager.startBackgroundKeepAlive()

        if storage.isGeofencingEnabled {
            let lat = storage.lastVehicleLat
            let lng = storage.lastVehicleLng
            if abs(lat) > 0.1 || abs(lng) > 0.1 {
                geofenceManager.registerGeofence(lat: lat, lng: lng)
            }
        }

        LogManager.shared.log("AutoLockService", "서비스 시작 - 대상: \(targetName ?? mac)")
        NotificationManager.shared.sendServiceStarted()
    }

    func stop() {
        geofenceManager.stopBackgroundKeepAlive()
        stopBLEScan()
        watchdogTimer?.cancel()
        watchdogTimer = nil
        sessionRefreshTimer?.cancel()
        sessionRefreshTimer = nil
        gpsPollTimer?.cancel()
        gpsPollTimer = nil
        signalLossTimer?.cancel()
        signalLossTimer = nil
        stationaryTimer?.cancel()
        stationaryTimer = nil
        motionManager?.stopActivityUpdates()
        motionManager = nil
        drivingMotionManager?.stopActivityUpdates()
        drivingMotionManager = nil
        isDriving = false
        isStationary = false
        isPredictiveUnlockPending = false
        isRunning = false
        smoothedRssi = nil
        rawRssi = nil
        proximityState = .far
        LogManager.shared.log("AutoLockService", "서비스 중지")
        NotificationManager.shared.sendServiceStopped()
        storage.saveWidgetData(isRunning: false, isLocked: nil, battery: nil, drivingRange: nil)
        WatchConnectivityManager.shared.sendStatusToWatch(isRunning: false, isLocked: nil, battery: nil, rssi: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refreshParkingLocation() {
        Task { await pollVehicleGPS() }
    }

    func updateWidgetStatus(battery: Int, drivingRange: Int) {
        storage.saveWidgetData(isRunning: isRunning, isLocked: nil, battery: battery, drivingRange: drivingRange)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func fetchVehicleStatus(vin: String) async throws -> VehicleStatus {
        guard let service = vehicleService else { throw BydError.notLoggedIn }
        let status = try await service.fetchVehicleStatus(vin: vin)
        lastKnownLocked = status.isLocked
        return status
    }

    func manualLock() {
        triggerCarAction(shouldUnlock: false, isManual: true)
    }

    func manualUnlock() {
        triggerCarAction(shouldUnlock: true, isManual: true)
    }

    func manualStartClimate() {
        guard let service = vehicleService,
              let vin = storage.selectedVin,
              let pin = storage.pin else { return }
        let temp  = Double(storage.acTargetTemp)
        let cycle = storage.acCycleMode
        let wind  = storage.acWindLevel > 0 ? storage.acWindLevel : nil
        Task {
            let ok = (try? await service.startClimate(vin: vin, temp: temp,
                                                      durationMinutes: 20,
                                                      cycleMode: cycle,
                                                      windLevel: wind, pin: pin)) ?? false
            await MainActor.run {
                self.lastApiResult = ok ? "에어컨 켜기 성공" : "에어컨 켜기 전송됨"
                self.lastApiTime   = Date()
            }
            LogManager.shared.log("API", "에어컨 수동 시작: \(temp)°C")
        }
    }

    func manualStopClimate() {
        guard let service = vehicleService,
              let vin = storage.selectedVin,
              let pin = storage.pin else { return }
        Task {
            let ok = (try? await service.stopClimate(vin: vin, pin: pin)) ?? false
            await MainActor.run {
                self.lastApiResult = ok ? "에어컨 끄기 성공" : "에어컨 끄기 전송됨"
                self.lastApiTime   = Date()
            }
            LogManager.shared.log("API", "에어컨 수동 종료")
        }
    }

    // MARK: - Background Task

    private func beginRssiPollingBGTask() {
        guard rssiPollingBGTaskID == .invalid else { return }
        rssiPollingBGTaskID = UIApplication.shared.beginBackgroundTask(withName: "RssiPolling") { [weak self] in
            // BG Task 만료 → iOS가 앱을 제한해 BLE가 끊길 수 있음. 신호 소실이 아님을 표시.
            self?.isIntentionalDisconnect = true
            self?.endRssiPollingBGTask()
        }
        LogManager.shared.log("BG", "RSSI 폴링 Background Task 시작")
    }

    private func endRssiPollingBGTask() {
        guard rssiPollingBGTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(rssiPollingBGTaskID)
        rssiPollingBGTaskID = .invalid
        LogManager.shared.log("BG", "RSSI 폴링 Background Task 종료")
    }

    // MARK: - BLE Scanning

    private func startBLEScan() {
        let options: [String: Any] = [
            CBCentralManagerOptionRestoreIdentifierKey: "byd.autolock.centralmanager"
        ]
        centralManager = CBCentralManager(delegate: self, queue: nil, options: options)
    }

    private func stopBLEScan() {
        rssiTimer?.cancel()
        rssiTimer = nil
        endRssiPollingBGTask()
        if let p = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(p)
            connectedPeripheral = nil
        }
        centralManager?.stopScan()
        isScanning = false
        scanModeDescription = "중지됨"
    }

    private func beginScanning() {
        guard centralManager?.state == .poweredOn else { return }
        // 정지 중이면 스캔 불필요 (연결 여부 무관하게 차단)
        if isStationary { return }
        if storage.isGeofencingEnabled && !isInsideGeofence { return }

        // 이미 연결되어 있으면 스킵
        if let p = connectedPeripheral, p.state == .connected { return }

        // 알고 있는 peripheral이면 바로 connect 시도
        if let p = connectedPeripheral {
            centralManager?.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
            scanModeDescription = "재연결 중..."
            LogManager.shared.log("BLE", "재연결 시도: \(p.name ?? "")")
            return
        }

        // 처음 탐색 - 스캔으로 기기 발견 후 connect
        centralManager?.scanForPeripherals(withServices: nil, options: nil)
        isScanning = true
        scanModeDescription = "스캔 중"
        LogManager.shared.log("BLE", "기기 탐색 스캔 시작")
    }

    private func startRssiTimer(for peripheral: CBPeripheral) {
        rssiTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: Self.rssiReadInterval)
        timer.setEventHandler {
            Task { @MainActor in
                guard peripheral.state == .connected else { return }
                peripheral.readRSSI()
            }
        }
        timer.resume()
        rssiTimer = timer
    }

    // MARK: - RSSI Processing

    private func processRSSI(_ rssi: Int) {
        rawRssi = rssi

        // 신호 복구 → grace timer 취소 + 알림 쿨다운 리셋
        if signalLossTimer != nil {
            LogManager.shared.log("BLE", "신호 복구. 잠금 유예 취소.")
            signalLossTimer?.cancel()
            signalLossTimer = nil
            NotificationManager.shared.resetSignalLostCooldown()
        }

        // 재연결 직후 첫 읽기: EMA/필터 없이 raw RSSI로 즉시 unlock 판단
        if isFirstRssiAfterConnect {
            isFirstRssiAfterConnect = false
            if rssi >= storage.unlockRssi && proximityState == .far && storage.isAutoUnlockOnApproach {
                if isDriving {
                    LogManager.shared.log("BLE", "재연결 즉시 unlock 차단 - 주행 중 (raw RSSI: \(rssi))")
                } else if lastKnownLocked == false {
                    // 이미 잠금 해제 상태 → API 불필요, proximityState만 near로
                    proximityState = .near
                } else {
                    LogManager.shared.log("BLE", "재연결 즉시 unlock (raw RSSI: \(rssi) >= unlockRssi: \(storage.unlockRssi))")
                    proximityState = .near
                    triggerCarAction(shouldUnlock: true, isManual: false)
                    return
                }
            }
        }

        // 선형 회귀 이상값 필터링
        let now = Date()
        rssiWindow.append(RssiPoint(time: now, dbm: rssi))
        if rssiWindow.count > Self.rssiWindowSize { rssiWindow.removeFirst() }

        if rssiWindow.count >= 4 {
            let predicted = linearRegressionPredict(rssiWindow)
            let deviation = abs(Double(rssi) - predicted)
            if deviation > 15 {
                consecutiveRejections += 1
                if consecutiveRejections < Self.maxRejections {
                    LogManager.shared.log("BLE", "RSSI 이상값 거부: \(rssi) dBm (예측: \(Int(predicted)), 편차: \(Int(deviation)))")
                    return
                }
            } else {
                consecutiveRejections = 0
            }
        }

        // 지수 이동 평균 (EMA)
        let alpha = Double(storage.rssiAlpha)
        if let prev = smoothedRssi {
            smoothedRssi = alpha * Double(rssi) + (1 - alpha) * prev
        } else {
            smoothedRssi = Double(rssi)
        }

        evaluateProximity()
    }

    private func handleSignalLoss() {
        guard smoothedRssi != nil else { return }
        smoothedRssi = nil
        rawRssi = nil
        rssiWindow.removeAll()
        isPredictiveUnlockPending = false

        if proximityState == .near {
            if isDriving {
                LogManager.shared.log("BLE", "신호 소실 - 주행 중이므로 알림 및 잠금 스킵.")
            } else {
                LogManager.shared.log("BLE", "신호 소실. \(Int(Self.signalLossGracePeriod))초 유예 후 잠금 예정.")
                NotificationManager.shared.sendSignalLost()
                startSignalLossTimer()
            }
        }
    }

    private func startSignalLossTimer() {
        signalLossTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.signalLossGracePeriod)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self, self.signalLossTimer != nil, self.proximityState == .near else { return }
                LogManager.shared.log("BLE", "신호 소실 \(Int(Self.signalLossGracePeriod))초 경과. 안전 잠금 실행.")
                self.signalLossTimer = nil
                self.proximityState = .far
                // updateCooldown: false → 재연결 직후 unlock이 cooldown에 차단되지 않도록
                self.triggerCarAction(shouldUnlock: false, isManual: false, updateCooldown: false)
            }
        }
        timer.resume()
        signalLossTimer = timer
    }

    // MARK: - Proximity Evaluation

    private func evaluateProximity() {
        guard let rssi = smoothedRssi else { return }
        let unlockThreshold = Double(storage.unlockRssi)
        let lockThreshold   = Double(storage.lockRssi)

        let wasNear = proximityState == .near

        // 예측 호출 후 RSSI가 예측 존 밖으로 내려가면 플래그 리셋 (오발 방지)
        if isPredictiveUnlockPending && !wasNear && rssi < unlockThreshold - Self.predictiveMargin {
            isPredictiveUnlockPending = false
            LogManager.shared.log("BLE", "예측 호출 취소 - RSSI 하강 (\(Int(rssi)))")
        }

        if !wasNear && rssi >= unlockThreshold {
            // 접근 감지 - 예측 호출이 이미 나간 경우 API 중복 호출 스킵
            let wasPredictive = isPredictiveUnlockPending
            proximityState = .near
            isPredictiveUnlockPending = false
            LogManager.shared.log("BLE", "접근 감지 (RSSI: \(Int(rssi)) >= \(Int(unlockThreshold)))\(wasPredictive ? " [예측 호출 중복 스킵]" : "")")
            if storage.isAutoUnlockOnApproach && !isDriving && !wasPredictive && lastKnownLocked != false {
                triggerCarAction(shouldUnlock: true, isManual: false)
            } else if isDriving {
                LogManager.shared.log("BLE", "잠금 해제 차단 - 주행 중")
            }
        } else if !wasNear && !isPredictiveUnlockPending
                    && rssi >= unlockThreshold - Self.predictiveMargin
                    && rssiWindow.count >= 5
                    && storage.isAutoUnlockOnApproach && !isDriving {
            // 예측적 사전 호출: 임계값 근접 + 상승 기울기 확인
            let slope = linearRegressionSlope(rssiWindow)
            if slope >= Self.predictiveMinSlope {
                isPredictiveUnlockPending = true
                LogManager.shared.log("BLE", "예측 사전 해제 (RSSI: \(Int(rssi)), 기울기: \(String(format: "%.2f", slope)) dBm/s)")
                triggerCarAction(shouldUnlock: true, isManual: false)
            }
        } else if wasNear && rssi <= lockThreshold {
            // 이탈 감지
            proximityState = .far
            isPredictiveUnlockPending = false
            LogManager.shared.log("BLE", "이탈 감지 (RSSI: \(Int(rssi)) <= \(Int(lockThreshold)))")
            if storage.isAutoLockOnDeparture && lastKnownLocked != true {
                triggerCarAction(shouldUnlock: false, isManual: false)
            }
        }
    }

    // MARK: - Car Action

    private func triggerCarAction(shouldUnlock: Bool, isManual: Bool, updateCooldown: Bool = true) {
        // 자동 동작 진동 방지 (수동 제어는 항상 허용)
        if !isManual {
            // 이미 같은 상태이면 명령 스킵 (중복 잠금/해제 방지, 방어적 처리)
            if let known = lastKnownLocked, known == !shouldUnlock {
                return
            }

            let now = Date()

            // 과다 반복 차단 중인지 확인
            if let suppressedUntil = autoActionSuppressedUntil, now < suppressedUntil {
                let remaining = Int(suppressedUntil.timeIntervalSince(now))
                LogManager.shared.log("AutoLockService", "자동 \(shouldUnlock ? "해제" : "잠금") 차단 - 반복 과다 (\(remaining)초 남음)")
                return
            }

            // 양방향 쿨다운 체크
            if !shouldUnlock, let t = lastAutoUnlockTime, now.timeIntervalSince(t) < Self.postUnlockLockCooldown {
                LogManager.shared.log("AutoLockService", "자동 잠금 차단 - unlock 쿨다운 중 (\(Int(now.timeIntervalSince(t)))초)")
                return
            }
            if shouldUnlock, let t = lastAutoLockTime, now.timeIntervalSince(t) < Self.postLockUnlockCooldown {
                LogManager.shared.log("AutoLockService", "자동 해제 차단 - lock 쿨다운 중 (\(Int(now.timeIntervalSince(t)))초)")
                return
            }

            // 슬라이딩 윈도우 횟수 체크
            recentAutoActionTimes.append(now)
            recentAutoActionTimes = recentAutoActionTimes.filter { now.timeIntervalSince($0) < Self.autoActionWindow }
            if recentAutoActionTimes.count > Self.maxAutoActionsInWindow {
                autoActionSuppressedUntil = now.addingTimeInterval(Self.suppressDuration)
                recentAutoActionTimes.removeAll()
                LogManager.shared.log("AutoLockService", "자동 동작 과다(\(Self.maxAutoActionsInWindow)회/\(Int(Self.autoActionWindow))초) → \(Int(Self.suppressDuration))초 차단")
                NotificationManager.shared.sendAutoActionSuppressed()
                return
            }
        }
        if !isManual && updateCooldown {
            if shouldUnlock { lastAutoUnlockTime = Date() }
            else            { lastAutoLockTime   = Date() }
        }

        guard let service = vehicleService,
              let vin = storage.selectedVin,
              let pin = storage.pin else {
            LogManager.shared.log("AutoLockService", "제어 실패: VIN 또는 PIN 없음")
            return
        }

        Task {
            do {
                // 자동 동작: fire-and-forget (폴링 없이 즉시 반환 → 체감 지연 제거)
                // 수동 동작: 폴링으로 결과 확인
                let result: Bool
                if isManual {
                    result = shouldUnlock
                        ? try await service.unlock(vin: vin, pin: pin)
                        : try await service.lock(vin: vin, pin: pin)
                } else {
                    if shouldUnlock { try await service.unlockAuto(vin: vin, pin: pin) }
                    else            { try await service.lockAuto(vin: vin, pin: pin) }
                    result = true
                }

                let isLocked = !shouldUnlock
                await MainActor.run {
                    self.lastKnownLocked = isLocked
                    self.lastApiResult = shouldUnlock
                        ? (result ? "잠금 해제 성공" : "잠금 해제 전송됨")
                        : (result ? "잠금 성공" : "잠금 전송됨")
                    self.lastApiTime = Date()
                    self.storage.saveWidgetData(isRunning: self.isRunning, isLocked: isLocked, battery: nil, drivingRange: nil)
                    WatchConnectivityManager.shared.sendStatusToWatch(isRunning: self.isRunning, isLocked: isLocked, battery: nil, rssi: self.rawRssi)
                    WidgetCenter.shared.reloadAllTimelines()
                    if shouldUnlock { self.endRssiPollingBGTask() }
                }

                LogManager.shared.log("API", "\(shouldUnlock ? "잠금 해제" : "잠금"): \(result ? "성공" : "전송됨") [\(isManual ? "수동" : "자동")]")
                NotificationManager.shared.sendLockUnlock(isUnlock: shouldUnlock, isManual: isManual)

                // 자동 에어컨
                if shouldUnlock && storage.isAutoAcOnUnlock {
                    let temp  = Double(storage.acTargetTemp)
                    let cycle = storage.acCycleMode
                    let wind  = storage.acWindLevel > 0 ? storage.acWindLevel : nil
                    _ = try? await service.startClimate(vin: vin, temp: temp, durationMinutes: 20,
                                                        cycleMode: cycle, windLevel: wind, pin: pin)
                    LogManager.shared.log("API", "에어컨 자동 시작: \(temp)°C")
                    NotificationManager.shared.sendAcStarted(temp: temp)
                } else if !shouldUnlock && storage.isAutoAcOffOnLock {
                    _ = try? await service.stopClimate(vin: vin, pin: pin)
                    LogManager.shared.log("API", "에어컨 자동 종료")
                    NotificationManager.shared.sendAcStopped()
                }

            } catch {
                await MainActor.run {
                    self.lastApiResult = "오류: \(error.localizedDescription)"
                    self.lastApiTime = Date()
                }
                LogManager.shared.log("API", "오류: \(error.localizedDescription)")
                // 자동 잠금 실패 시 45초 후 1회 재시도 (6002 등 일시적 통신 오류 대비)
                if !isManual && !shouldUnlock {
                    LogManager.shared.log("API", "자동 잠금 실패 - 45초 후 재시도 예정")
                    try? await Task.sleep(nanoseconds: 45_000_000_000)
                    guard await MainActor.run(body: { self.proximityState == .far }) else { return }
                    try? await service.lockAuto(vin: vin, pin: pin)
                    await MainActor.run { self.lastKnownLocked = true }
                    LogManager.shared.log("API", "자동 잠금 재시도 완료")
                }
            }
        }
    }

    // MARK: - Linear Regression

    /// RSSI 상승/하강 기울기 (dBm/초). 양수 = 접근, 음수 = 이탈
    private func linearRegressionSlope(_ points: [RssiPoint]) -> Double {
        guard let first = points.first else { return 0 }
        let n = Double(points.count)
        let t0 = first.time.timeIntervalSince1970
        let xs = points.map { $0.time.timeIntervalSince1970 - t0 }
        let ys = points.map { Double($0.dbm) }
        let sumX  = xs.reduce(0, +)
        let sumY  = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)
        let denom = n * sumX2 - sumX * sumX
        guard abs(denom) > 1e-9 else { return 0 }
        return (n * sumXY - sumX * sumY) / denom
    }

    private func linearRegressionPredict(_ points: [RssiPoint]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        let n = Double(points.count)
        let t0 = first.time.timeIntervalSince1970
        let xs = points.map { $0.time.timeIntervalSince1970 - t0 }
        let ys = points.map { Double($0.dbm) }
        let sumX  = xs.reduce(0, +)
        let sumY  = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)
        let denom = n * sumX2 - sumX * sumX
        guard abs(denom) > 1e-9 else { return sumY / n }
        let slope     = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        let lastT = last.time.timeIntervalSince1970 - t0
        return slope * lastT + intercept
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        watchdogTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.watchdogInterval, repeating: Self.watchdogInterval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.smoothedRssi == nil {
                    LogManager.shared.log("Watchdog", "BLE 스캔 갱신")
                    self.isStationary = false
                    self.beginScanning()
                    self.startStationaryTimer()
                }
            }
        }
        timer.resume()
        watchdogTimer = timer
    }

    // MARK: - Session Refresh

    private func setupSessionCallbacks() async {
        await vehicleService?.setOnSessionUpdated { [weak self] uid, sign, encry in
            Task { @MainActor in
                self?.storage.userId     = uid
                self?.storage.signToken  = sign
                self?.storage.encryToken = encry
            }
        }
        await vehicleService?.setOnSessionExpired { [weak self] in
            Task { @MainActor in
                LogManager.shared.log("Session", "세션 만료. 자동 재로그인 시도 중...")
            }
        }
    }

    private func startSessionRefresh() {
        sessionRefreshTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.sessionRefreshInterval, repeating: Self.sessionRefreshInterval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self,
                      let user = self.storage.username,
                      let pwd  = self.storage.password else { return }
                let svc = self.vehicleService
                do {
                    _ = try await svc?.login(username: user, password: pwd)
                    LogManager.shared.log("Session", "세션 갱신 성공")
                } catch {
                    LogManager.shared.log("Session", "세션 갱신 실패: \(error.localizedDescription)")
                }
            }
        }
        timer.resume()
        sessionRefreshTimer = timer
    }

    // MARK: - GPS Polling

    private func startGpsPoll() {
        gpsPollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.gpsPollInterval, repeating: Self.gpsPollInterval)
        timer.setEventHandler { [weak self] in
            Task { await self?.pollVehicleGPS() }
        }
        timer.resume()
        gpsPollTimer = timer
    }

    private func pollVehicleGPS() async {
        guard let service = vehicleService, let vin = storage.selectedVin else { return }
        do {
            let gps = try await service.fetchGpsInfo(vin: vin)
            guard gps.isValid else { return }
            storage.lastVehicleLat    = gps.latitude
            storage.lastVehicleLng    = gps.longitude
            storage.lastVehicleTime   = gps.timestamp
            storage.lastVehicleSource = "API"
            lastParkingLat  = gps.latitude
            lastParkingLng  = gps.longitude
            lastParkingTime = Date(timeIntervalSince1970: gps.timestamp)
            // 주행 중에는 지오펜스 재등록 차단
            // BYD GPS API가 실시간 speed를 반환하지 않아 gps.speed만으로는 주행 여부 판단 불가
            if storage.isGeofencingEnabled && !isDriving {
                geofenceManager.registerGeofence(lat: gps.latitude, lng: gps.longitude)
            }
            LogManager.shared.log("GPS", "차량 위치 갱신: \(gps.latitude), \(gps.longitude) speed:\(Int(gps.speed))km/h")
        } catch {
            LogManager.shared.log("GPS", "위치 조회 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - Stationary Detection (CoreMotion)

    private func startStationaryTimer() {
        stationaryTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.stationaryTimeout)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self, self.smoothedRssi == nil else { return }
                self.isStationary = true
                self.stopBLEScan()
                LogManager.shared.log("Motion", "5분간 정지. BLE 스캔 일시 중단.")
                self.startMotionUpdates()
            }
        }
        timer.resume()
        stationaryTimer = timer
    }

    private func startMotionUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        let manager = CMMotionActivityManager()
        motionManager = manager
        manager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity, activity.confidence != .low else { return }
            if activity.walking || activity.running || activity.automotive {
                Task { @MainActor in
                    // motionManager != nil 체크로 중복 콜백 차단 (동일 시각 다수 호출 방지)
                    guard let self, self.motionManager != nil else { return }
                    self.isStationary = false
                    self.motionManager = nil
                    manager.stopActivityUpdates()
                    LogManager.shared.log("Motion", "움직임 감지. BLE 스캔 재개.")
                    self.beginScanning()
                    self.startStationaryTimer()
                }
            }
        }
    }

    private func startDrivingDetection() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        let manager = CMMotionActivityManager()
        drivingMotionManager = manager
        manager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity, activity.confidence != .low else { return }
            Task { @MainActor in
                guard let self else { return }
                let driving = activity.automotive
                if self.isDriving != driving {
                    self.isDriving = driving
                    LogManager.shared.log("Motion", driving ? "주행 중 감지 - 자동 잠금 해제 일시 차단" : "주행 종료 감지 - 자동 잠금 해제 재개")
                    if !driving && self.storage.isGeofencingEnabled {
                        // 주행 종료 → 현재 주차 위치로 지오펜스 즉시 갱신
                        Task { await self.pollVehicleGPS() }
                        // 지오펜스 외부: 지오펜스 이탈이 주행 종료보다 먼저 발생한 케이스
                        // BLE RSSI 기반 이탈 감지가 불가하므로 즉시 잠금
                        if !self.isInsideGeofence && self.storage.isAutoLockOnDeparture
                           && self.lastKnownLocked != true {
                            LogManager.shared.log("Motion", "주행 종료 + 지오펜스 외부 → 자동 잠금 실행")
                            self.triggerCarAction(shouldUnlock: false, isManual: false)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension AutoLockService: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                LogManager.shared.log("BLE", "블루투스 켜짐. 스캔 시작.")
                self.beginScanning()
                self.startStationaryTimer()
            case .poweredOff:
                LogManager.shared.log("BLE", "블루투스 꺼짐.")
                self.smoothedRssi = nil
                self.rawRssi = nil
                self.scanModeDescription = "블루투스 꺼짐"
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        LogManager.shared.log("BLE", "CBCentralManager 상태 복원")
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            Task { @MainActor in
                for p in peripherals {
                    let uuidMatches = p.identifier.uuidString == self.targetMac
                    let nameMatches = p.name != nil && p.name == self.targetName
                    guard uuidMatches || nameMatches else { continue }
                    p.delegate = self
                    self.connectedPeripheral = p
                    if p.state == .connected {
                        self.isFirstRssiAfterConnect = true
                        self.beginRssiPollingBGTask()
                        self.startRssiTimer(for: p)
                        self.scanModeDescription = "연결됨 (복원)"
                    } else {
                        central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
                        self.scanModeDescription = "재연결 중..."
                    }
                    LogManager.shared.log("BLE", "상태 복원: \(p.name ?? p.identifier.uuidString)")
                    break
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard RSSI.intValue != 127 else { return }
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "")

        Task { @MainActor in
            guard let targetMac = self.targetMac else { return }
            let uuidMatches = peripheral.identifier.uuidString == targetMac
            let nameMatches = !name.isEmpty && name == (self.targetName ?? "")
            guard uuidMatches || nameMatches else { return }

            // 발견 → 스캔 중지 후 connect
            central.stopScan()
            self.isScanning = false
            self.connectedPeripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
            self.scanModeDescription = "연결 중..."
            LogManager.shared.log("BLE", "타겟 발견 → 연결 시도: \(name)")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.scanModeDescription = "연결됨"
            LogManager.shared.log("BLE", "BLE 연결 성공: \(peripheral.name ?? "")")
            self.isFirstRssiAfterConnect = true
            self.isPredictiveUnlockPending = false
            // 지오펜스 이탈 중에는 RSSI 폴링 시작 안 함
            guard !self.storage.isGeofencingEnabled || self.isInsideGeofence else {
                LogManager.shared.log("BLE", "지오펜스 외부 - RSSI 폴링 스킵")
                return
            }
            self.beginRssiPollingBGTask()
            self.startRssiTimer(for: peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            LogManager.shared.log("BLE", "BLE 연결 실패: \(error?.localizedDescription ?? "unknown")")
            self.scanModeDescription = "연결 실패"
            guard self.isRunning else { return }
            // 5초 후 재시도
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self.beginScanning()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.rssiTimer?.cancel()
            self.rssiTimer = nil
            self.endRssiPollingBGTask()
            LogManager.shared.log("BLE", "BLE 연결 끊김: \(error?.localizedDescription ?? "정상 종료")")
            // BG Task 만료로 인한 끊김은 신호 소실이 아님 → 잠금 스킵
            let wasIntentional = self.isIntentionalDisconnect
            self.isIntentionalDisconnect = false
            if !wasIntentional {
                self.handleSignalLoss()
            }
            guard self.isRunning else { return }
            // 지오펜스 이탈 중에는 재연결 시도 안 함
            if self.storage.isGeofencingEnabled && !self.isInsideGeofence {
                self.scanModeDescription = "지오펜스 외부"
                return
            }
            // 즉시 재연결 시도 (iOS가 백그라운드에서 자동 재연결 큐에 등록)
            central.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
            self.scanModeDescription = "재연결 중..."
        }
    }
}

// MARK: - CBPeripheralDelegate

extension AutoLockService: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil, RSSI.intValue != 127 else { return }
        Task { @MainActor in
            self.processRSSI(RSSI.intValue)
        }
    }
}

// MARK: - GeofenceDelegate

extension AutoLockService: GeofenceManagerDelegate {

    func didEnterGeofence() {
        guard isRunning else { return }
        isInsideGeofence = true
        // 주행 중에는 BLE 재개만 차단 (isInsideGeofence 상태는 정확하게 유지)
        guard !isDriving else { return }
        isStationary = false
        LogManager.shared.log("Geofence", "지오펜스 진입. BLE 재개.")
        if let p = connectedPeripheral, p.state == .connected {
            beginRssiPollingBGTask()
            startRssiTimer(for: p)
        } else {
            beginScanning()
        }
        startStationaryTimer()
    }

    func didExitGeofence() {
        guard isRunning else { return }
        isInsideGeofence = false
        // 이미 연결된 BLE는 유지 (재진입 시 바로 RSSI 재개)
        // 스캔과 RSSI 폴링만 중단
        rssiTimer?.cancel()
        rssiTimer = nil
        endRssiPollingBGTask()
        centralManager?.stopScan()
        isScanning = false
        scanModeDescription = "지오펜스 외부"
        smoothedRssi = nil
        rawRssi = nil
        LogManager.shared.log("Geofence", "지오펜스 이탈. BLE 스캔 중단 (연결 유지).")
    }
}

// MARK: - BydVehicleService Callbacks (actor isolation helper)

private extension BydVehicleService {
    func setOnSessionUpdated(_ handler: @escaping (String, String, String) -> Void) async {
        self.onSessionUpdated = handler
    }
    func setOnSessionExpired(_ handler: @escaping () -> Void) async {
        self.onSessionExpired = handler
    }
}
