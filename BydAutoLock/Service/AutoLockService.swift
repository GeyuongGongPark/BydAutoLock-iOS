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

    // 워치독 타이머 (5분)
    private var watchdogTimer: DispatchSourceTimer?
    private static let watchdogInterval: TimeInterval = 300

    // 정지 감지 (5분)
    private var motionManager: CMMotionActivityManager?
    private var stationaryTimer: DispatchSourceTimer?
    private static let stationaryTimeout: TimeInterval = 300

    // 주행 중 감지 (상시)
    private var drivingMotionManager: CMMotionActivityManager?
    private var lastKnownSpeed: Double = 0
    private var lastSpeedTime: Date?

    // RSSI 로그 집계 (10초 주기)
    private var rssiLogTimer: Timer?
    private var rssiSamples = [Int]()

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
        storage.saveWidgetData(isRunning: true, isLocked: nil, battery: nil, rssi: nil)
        WatchConnectivityManager.shared.sendStatusToWatch(isRunning: true, isLocked: nil, battery: nil, rssi: nil)
        WidgetCenter.shared.reloadAllTimelines()

        if storage.isGeofencingEnabled {
            geofenceManager.setup()
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
        stopBLEScan()
        watchdogTimer?.cancel()
        sessionRefreshTimer?.cancel()
        gpsPollTimer?.cancel()
        rssiLogTimer?.invalidate()
        stationaryTimer?.cancel()
        drivingMotionManager?.stopActivityUpdates()
        drivingMotionManager = nil
        isDriving = false
        isRunning = false
        smoothedRssi = nil
        rawRssi = nil
        proximityState = .far
        LogManager.shared.log("AutoLockService", "서비스 중지")
        NotificationManager.shared.sendServiceStopped()
        storage.saveWidgetData(isRunning: false, isLocked: nil, battery: nil, rssi: nil)
        WatchConnectivityManager.shared.sendStatusToWatch(isRunning: false, isLocked: nil, battery: nil, rssi: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refreshParkingLocation() {
        Task { await pollVehicleGPS() }
    }

    func updateWidgetBattery(_ battery: Int) {
        storage.saveWidgetData(isRunning: isRunning, isLocked: nil, battery: battery, rssi: rawRssi)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func fetchVehicleStatus(vin: String) async throws -> VehicleStatus {
        guard let service = vehicleService else { throw BydError.notLoggedIn }
        return try await service.fetchVehicleStatus(vin: vin)
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
        if isStationary && !isNear() { return }
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

    private func isNear() -> Bool { proximityState == .near }

    // MARK: - RSSI Processing

    private func processRSSI(_ rssi: Int) {
        rawRssi = rssi

        // 재연결 직후 첫 읽기: EMA/필터 없이 raw RSSI로 즉시 unlock 판단
        if isFirstRssiAfterConnect {
            isFirstRssiAfterConnect = false
            if rssi >= storage.unlockRssi && proximityState == .far && storage.isAutoUnlockOnApproach {
                if isDriving {
                    LogManager.shared.log("BLE", "재연결 즉시 unlock 차단 - 주행 중 (raw RSSI: \(rssi))")
                } else {
                    LogManager.shared.log("BLE", "재연결 즉시 unlock (raw RSSI: \(rssi) >= unlockRssi: \(storage.unlockRssi))")
                    proximityState = .near
                    triggerCarAction(shouldUnlock: true, isManual: false)
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

        // RSSI 집계 로깅
        rssiSamples.append(rssi)

        evaluateProximity()
    }

    private func handleSignalLoss() {
        guard smoothedRssi != nil else { return }
        smoothedRssi = nil
        rawRssi = nil
        rssiWindow.removeAll()

        if proximityState == .near {
            LogManager.shared.log("BLE", "신호 소실. 즉시 안전 잠금 실행.")
            NotificationManager.shared.sendSignalLost()
            proximityState = .far
            triggerCarAction(shouldUnlock: false, isManual: false)
        }
    }

    // MARK: - Proximity Evaluation

    private func evaluateProximity() {
        guard let rssi = smoothedRssi else { return }
        let unlockThreshold = Double(storage.unlockRssi)
        let lockThreshold   = Double(storage.lockRssi)

        let wasNear = proximityState == .near

        if !wasNear && rssi >= unlockThreshold {
            // 접근 감지
            proximityState = .near
            LogManager.shared.log("BLE", "접근 감지 (RSSI: \(Int(rssi)) >= \(Int(unlockThreshold)))")
            if storage.isAutoUnlockOnApproach {
                if isDriving {
                    LogManager.shared.log("BLE", "잠금 해제 차단 - 주행 중")
                } else {
                    triggerCarAction(shouldUnlock: true, isManual: false)
                }
            }
        } else if wasNear && rssi <= lockThreshold {
            // 이탈 감지
            proximityState = .far
            LogManager.shared.log("BLE", "이탈 감지 (RSSI: \(Int(rssi)) <= \(Int(lockThreshold)))")
            if storage.isAutoLockOnDeparture {
                triggerCarAction(shouldUnlock: false, isManual: false)
            }
        }
    }

    // MARK: - Car Action

    private func triggerCarAction(shouldUnlock: Bool, isManual: Bool) {
        // 자동 동작 진동 방지 (수동 제어는 항상 허용)
        if !isManual {
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
        if !isManual {
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
                let result = shouldUnlock
                    ? try await service.unlock(vin: vin, pin: pin)
                    : try await service.lock(vin: vin, pin: pin)

                let isLocked = !shouldUnlock
                await MainActor.run {
                    self.lastApiResult = shouldUnlock
                        ? (result ? "잠금 해제 성공" : "잠금 해제 전송됨")
                        : (result ? "잠금 성공" : "잠금 전송됨")
                    self.lastApiTime = Date()
                    self.storage.saveWidgetData(isRunning: self.isRunning, isLocked: isLocked, battery: nil, rssi: self.rawRssi)
                    WatchConnectivityManager.shared.sendStatusToWatch(isRunning: self.isRunning, isLocked: isLocked, battery: nil, rssi: self.rawRssi)
                    WidgetCenter.shared.reloadAllTimelines()
                    // unlock 성공 시 Background Task 종료 (더 이상 RSSI 폴링 불필요)
                    if shouldUnlock { self.endRssiPollingBGTask() }
                }

                LogManager.shared.log("API", "\(shouldUnlock ? "잠금 해제" : "잠금"): \(result ? "성공" : "전송됨")")
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
            }
        }
    }

    // MARK: - Linear Regression

    private func linearRegressionPredict(_ points: [RssiPoint]) -> Double {
        let n = Double(points.count)
        let t0 = points.first!.time.timeIntervalSince1970
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
        let lastT = (points.last!.time.timeIntervalSince1970 - t0)
        return slope * lastT + intercept
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.watchdogInterval, repeating: Self.watchdogInterval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.smoothedRssi == nil && !self.isStationary {
                    LogManager.shared.log("Watchdog", "BLE 스캔 갱신")
                    self.beginScanning()
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
            lastKnownSpeed = gps.speed
            lastSpeedTime  = Date()
            if gps.speed > 5.0 { isDriving = true }
            storage.lastVehicleLat    = gps.latitude
            storage.lastVehicleLng    = gps.longitude
            storage.lastVehicleTime   = gps.timestamp
            storage.lastVehicleSource = "API"
            lastParkingLat  = gps.latitude
            lastParkingLng  = gps.longitude
            lastParkingTime = Date(timeIntervalSince1970: gps.timestamp)
            if storage.isGeofencingEnabled {
                geofenceManager.registerGeofence(lat: gps.latitude, lng: gps.longitude)
            }
            LogManager.shared.log("GPS", "차량 위치 갱신: \(gps.latitude), \(gps.longitude)")
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
                    guard let self else { return }
                    self.isStationary = false
                    manager.stopActivityUpdates()
                    self.motionManager = nil
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
            self.handleSignalLoss()
            guard self.isRunning else { return }
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
        isInsideGeofence = true
        LogManager.shared.log("Geofence", "지오펜스 진입. BLE 스캔 시작.")
        beginScanning()
        startStationaryTimer()
    }

    func didExitGeofence() {
        isInsideGeofence = false
        // peripheral 참조는 유지하고 연결만 해제 (재진입 시 바로 재연결)
        rssiTimer?.cancel()
        rssiTimer = nil
        if let p = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(p)
        }
        centralManager?.stopScan()
        isScanning = false
        scanModeDescription = "지오펜스 외부"
        smoothedRssi = nil
        rawRssi = nil
        LogManager.shared.log("Geofence", "지오펜스 이탈. BLE 연결 해제.")
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
