import Foundation
import CoreBluetooth

enum BleDirectAction { case lock, unlock }

enum BleDirectError: LocalizedError {
    case notConnected
    case serviceNotFound
    case characteristicNotFound
    case randomExchangeFailed
    case authFailed(UInt8)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected:            return "BLE 연결 없음"
        case .serviceNotFound:         return "차량 BLE 서비스 없음"
        case .characteristicNotFound:  return "BLE 특성 없음"
        case .randomExchangeFailed:    return "RandomExchange 파싱 실패"
        case .authFailed(let code):    return "BLE 인증 실패 (code=0x\(String(code, radix: 16)))"
        case .timeout:                 return "BLE 응답 타임아웃"
        }
    }
}

/// BLE 직접 차량 제어 세션 오케스트레이터.
///
/// `perform(action:peripheral:dkey:)`를 호출하면 WakeUp → RandomExchange → Authentication → Control
/// 순으로 GATT 프레임을 교환해 차량을 제어한다.
///
/// - `peripheral.delegate`를 일시적으로 자신으로 교체하고 `defer`로 복원하므로,
///   호출 중 AutoLockService의 `didReadRSSI` 콜백은 잠시 수신되지 않는다.
/// - AutoLockService와 같이 `queue: nil` (메인 큐)로 초기화된 CBCentralManager를 공유하므로,
///   CoreBluetooth 콜백은 모두 메인 큐에서 호출된다.
@MainActor
final class BleDirectController: NSObject {

    private let codec = BleCodec()
    private let assembler = BleFrameAssembler()
    private var sendChar: CBCharacteristic?
    private var receiveChar: CBCharacteristic?

    // Continuation for service/characteristic discovery
    private var discoveryContinuation: CheckedContinuation<Void, Error>?
    // Continuation for waiting on a single notify frame
    private var frameContinuation: CheckedContinuation<[UInt8], Error>?

    // MARK: - Public

    func perform(action: BleDirectAction, peripheral: CBPeripheral, dkey: String) async throws {
        guard peripheral.state == .connected else { throw BleDirectError.notConnected }

        logCredentialSnapshot(dkey: dkey, action: action, peripheral: peripheral)

        let previousDelegate = peripheral.delegate
        peripheral.delegate = self

        codec.clearSession()
        assembler.reset()
        sendChar = nil
        receiveChar = nil

        defer {
            if let rc = receiveChar {
                peripheral.setNotifyValue(false, for: rc)
            }
            peripheral.delegate = previousDelegate
            discoveryContinuation = nil
            frameContinuation = nil
        }

        // 1. Discover service & characteristics
        try await discoverServicesAndCharacteristics(peripheral: peripheral)
        logCharacteristicProperties()

        // 2. Enable notifications on receive characteristic
        let canNotify = receiveChar!.properties.contains(.notify) || receiveChar!.properties.contains(.indicate)
        LogManager.shared.log("BLE", "notify 활성화 요청 (notify/indicate=\(canNotify))")
        peripheral.setNotifyValue(true, for: receiveChar!)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms settle

        // 3. WakeUp
        let wake = codec.createWakeUpFrame()
        peripheral.writeValue(Data(wake), for: sendChar!, type: .withoutResponse)
        LogManager.shared.log("BLE", "WakeUp 전송 (\(wake.count)B): \(hex(wake)) write=withoutResponse")
        try await Task.sleep(nanoseconds: 300_000_000) // 300ms

        // 4. RandomExchange
        let storage = StorageManager.shared
        let keyNumber = UInt8(storage.bleKeyNumber & 0xFF)
        let randFrame = codec.createRandomExchangeFrame(keyNumber: keyNumber)
        peripheral.writeValue(Data(randFrame), for: sendChar!, type: .withoutResponse)
        LogManager.shared.log("BLE", "RandomExchange 전송 (keyNumber=\(keyNumber), 저장됨=\(storage.hasStoredBleKeyNumber), frame[11]=\(String(format: "0x%02x", randFrame[11])))")
        LogManager.shared.log("BLE", "RandomExchange 송신(\(randFrame.count)B): \(hex(randFrame))")
        let randRespRaw = try await waitForFrame(timeout: 5.0)
        let randStripped = randRespRaw.count >= 2 && randRespRaw[0] == 0xA5 && randRespRaw[1] == 0x5A
        let randResp = stripResponseHeader(randRespRaw)
        LogManager.shared.log("BLE", "RandomExchange 원시(\(randRespRaw.count)B, A55A제거=\(randStripped)): \(hex(randRespRaw))")
        LogManager.shared.log("BLE", "RandomExchange strip후(\(randResp.count)B): \(hex(randResp))")
        guard let parsed = codec.parseRandomExchange(randResp) else {
            let type = randResp.first.map { String(format: "0x%02x", $0) } ?? "없음"
            let cmd = randResp.count > 1 ? String(format: "0x%02x", randResp[1]) : "없음"
            LogManager.shared.log("BLE", "RandomExchange 파싱 실패 type=\(type) cmd=\(cmd) len=\(randResp.count)")
            throw BleDirectError.randomExchangeFailed
        }
        LogManager.shared.log("BLE", "RandomExchange 완료 keyState=0x\(String(parsed.keyState, radix: 16)) crcCheck=0x\(String(parsed.crcCheckResult, radix: 16)) vehicleRandom=\(hex(parsed.vehicleRandom))")

        // 5. Authentication
        LogManager.shared.log("BLE", "dkey \(describeDkey(dkey))")
        let authFrame = try codec.createAuthenticationFrame(dkey: dkey)
        peripheral.writeValue(Data(authFrame), for: sendChar!, type: .withoutResponse)
        LogManager.shared.log("BLE", "Authentication 전송 (\(authFrame.count)B): \(hex(authFrame))")
        let authRespRaw = try await waitForFrame(timeout: 5.0)
        let authStripped = authRespRaw.count >= 2 && authRespRaw[0] == 0xA5 && authRespRaw[1] == 0x5A
        let authResp = stripResponseHeader(authRespRaw)
        LogManager.shared.log("BLE", "Authentication 원시(\(authRespRaw.count)B, A55A제거=\(authStripped)): \(hex(authRespRaw))")
        LogManager.shared.log("BLE", "Authentication 응답(\(authResp.count)B): \(hex(authResp))")
        let authType = authResp.first.map { String(format: "0x%02x", $0) } ?? "없음"
        let authCmd = authResp.count > 1 ? String(format: "0x%02x", authResp[1]) : "없음"
        let authResult = BleCodec.parseAuthenticationResult(authResp)
        LogManager.shared.log("BLE", "Authentication 파싱 type=\(authType) cmd=\(authCmd) result=0x\(String(authResult, radix: 16))")
        guard authResult == 0x01 else {
            LogManager.shared.log("BLE", "Authentication 실패 (result=0x\(String(authResult, radix: 16)))")
            throw BleDirectError.authFailed(authResult)
        }
        LogManager.shared.log("BLE", "Authentication 성공")

        // 6. Control
        let controlCode: UInt8 = action == .unlock
            ? BleCodec.getControlCode(9001)  // 잠금 해제
            : BleCodec.getControlCode(9002)  // 잠금
        let controlFrame = try codec.createControlFrame(controlCode: controlCode)
        peripheral.writeValue(Data(controlFrame), for: sendChar!, type: .withoutResponse)
        LogManager.shared.log("BLE", "Control 전송 (code=0x\(String(controlCode, radix: 16))) (\(controlFrame.count)B): \(hex(controlFrame))")
        let controlRaw = try await waitForFrame(timeout: 5.0)
        let controlResp = stripResponseHeader(controlRaw)
        LogManager.shared.log("BLE", "Control 원시(\(controlRaw.count)B): \(hex(controlRaw))")
        LogManager.shared.log("BLE", "Control strip후(\(controlResp.count)B): \(hex(controlResp))")
        let controlResult = BleCodec.parseControlResult(controlResp)
        let controlType = BleCodec.parseResponseType(controlResp)
        let controlCmd = BleCodec.parseResponseCommandType(controlResp)
        let parsedCode = BleCodec.parseControlCode(controlResp)
        let doorStates = BleCodec.parseDoorStates(controlResp)
        LogManager.shared.log("BLE", "Control 파싱 type=0x\(String(controlType, radix: 16)) cmd=0x\(String(controlCmd, radix: 16)) code=0x\(String(parsedCode, radix: 16)) result=\(controlResult) door=0x\(String(doorStates, radix: 16))")
        // result == 0x00 이 성공, 그 외는 경고 로그만 남기고 성공으로 처리 (응답 있으면 명령 전달됨)
    }

    // MARK: - Private

    /// 차량 응답 프레임 앞에 붙는 `A5 5A` 헤더를 제거한다.
    /// 실기기 로그에서 차량이 `A5 5A [type] [cmd] ...` 형태로 응답함을 확인.
    private func stripResponseHeader(_ frame: [UInt8]) -> [UInt8] {
        if frame.count >= 2, frame[0] == 0xA5, frame[1] == 0x5A {
            return Array(frame.dropFirst(2))
        }
        return frame
    }

    private func logCredentialSnapshot(dkey: String, action: BleDirectAction, peripheral: CBPeripheral) {
        let storage = StorageManager.shared
        let vinTail = storage.watchVin.map { "***\($0.suffix(4))" } ?? "없음"
        LogManager.shared.log("BLE", "세션 시작 action=\(action == .unlock ? "unlock" : "lock") peripheral=\(peripheral.name ?? "?") state=\(peripheral.state.rawValue)")
        LogManager.shared.log("BLE", "저장 자격증명: dkey \(describeDkey(dkey)), keyNumber=\(storage.bleKeyNumber) 저장됨=\(storage.hasStoredBleKeyNumber), protocol=\(storage.bleAuthProtocol) 저장됨=\(storage.hasStoredBleAuthProtocol), password=\(storage.blePassword != nil ? "있음" : "없음"), mac=\(storage.bleMacAddress ?? "없음"), watchVin=\(vinTail), userType=\(storage.watchUserType ?? "없음")")
        if let json = storage.watchVehicleInfoJson,
           let data = json.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            LogManager.shared.log("BLE", "저장 vehicle JSON 구조: \(BydWatchKeyService.describeDictShape(dict))")
            _ = BydWatchKeyService.extractBleInfo(fromVehicleConfig: dict)
        } else {
            LogManager.shared.log("BLE", "저장 vehicle JSON 없음 (등록 로그 없이 keyNumber 출처 확인 불가)")
        }
    }

    private func logCharacteristicProperties() {
        let send = sendChar.map(describeProperties) ?? "없음"
        let recv = receiveChar.map(describeProperties) ?? "없음"
        let writeNR = sendChar?.properties.contains(.writeWithoutResponse) ?? false
        LogManager.shared.log("BLE", "GATT 특성 send={\(send)} recv={\(recv)} — 송신은 withoutResponse 사용, writeNR지원=\(writeNR)")
    }

    private func describeProperties(_ c: CBCharacteristic) -> String {
        var parts: [String] = []
        if c.properties.contains(.read) { parts.append("read") }
        if c.properties.contains(.write) { parts.append("write") }
        if c.properties.contains(.writeWithoutResponse) { parts.append("writeNR") }
        if c.properties.contains(.notify) { parts.append("notify") }
        if c.properties.contains(.indicate) { parts.append("indicate") }
        return "\(c.uuid.uuidString) [\(parts.joined(separator: ","))]"
    }

    private func describeDkey(_ dkey: String) -> String {
        let t = dkey.trimmingCharacters(in: .whitespacesAndNewlines)
        let isHex = t.count % 2 == 0 && t.allSatisfy(\.isHexDigit)
        let charset: String
        if t.contains("-") { charset = "uuid-like" }
        else if isHex { charset = "hex" }
        else { charset = "other" }
        let casing: String
        if t == t.uppercased() { casing = "upper" }
        else if t == t.lowercased() { casing = "lower" }
        else { casing = "mixed" }
        return "len=\(t.count) charset=\(charset) case=\(casing) valid=\(BleCodec.isValidDkey(t))"
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func discoverServicesAndCharacteristics(peripheral: CBPeripheral) async throws {
        try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else { return }
            self.discoveryContinuation = continuation
            peripheral.discoverServices([CBUUID(string: BleCodec.serviceUUID)])
            // Timeout guard
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                await MainActor.run { [weak self] in
                    guard let self, let c = self.discoveryContinuation else { return }
                    self.discoveryContinuation = nil
                    LogManager.shared.log("BLE", "서비스/특성 탐색 타임아웃 (10s)")
                    c.resume(throwing: BleDirectError.timeout)
                }
            }
        }
    }

    private func waitForFrame(timeout: TimeInterval) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else { return }
            self.frameContinuation = continuation
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await MainActor.run { [weak self] in
                    guard let self, let c = self.frameContinuation else { return }
                    self.frameContinuation = nil
                    LogManager.shared.log("BLE", "프레임 대기 타임아웃 (\(timeout)s)")
                    c.resume(throwing: BleDirectError.timeout)
                }
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BleDirectController: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                LogManager.shared.log("BLE", "서비스 탐색 실패: \(error.localizedDescription)")
                self.discoveryContinuation?.resume(throwing: error)
                self.discoveryContinuation = nil
                return
            }
            let found = peripheral.services?.map { $0.uuid.uuidString } ?? []
            LogManager.shared.log("BLE", "서비스 탐색 완료: \(found.joined(separator: ", ")) (대상=\(BleCodec.serviceUUID))")
            guard let service = peripheral.services?.first(where: {
                $0.uuid == CBUUID(string: BleCodec.serviceUUID)
            }) else {
                self.discoveryContinuation?.resume(throwing: BleDirectError.serviceNotFound)
                self.discoveryContinuation = nil
                return
            }
            peripheral.discoverCharacteristics([
                CBUUID(string: BleCodec.sendCharacteristicUUID),
                CBUUID(string: BleCodec.receiveCharacteristicUUID)
            ], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                LogManager.shared.log("BLE", "특성 탐색 실패: \(error.localizedDescription)")
                self.discoveryContinuation?.resume(throwing: error)
                self.discoveryContinuation = nil
                return
            }
            let chars = service.characteristics ?? []
            LogManager.shared.log("BLE", "특성 탐색 완료: \(chars.map { "\($0.uuid.uuidString)" }.joined(separator: ", "))")
            self.sendChar = chars.first {
                $0.uuid == CBUUID(string: BleCodec.sendCharacteristicUUID)
            }
            self.receiveChar = chars.first {
                $0.uuid == CBUUID(string: BleCodec.receiveCharacteristicUUID)
            }
            guard self.sendChar != nil, self.receiveChar != nil else {
                LogManager.shared.log("BLE", "특성 매칭 실패 send=\(self.sendChar != nil) recv=\(self.receiveChar != nil)")
                self.discoveryContinuation?.resume(throwing: BleDirectError.characteristicNotFound)
                self.discoveryContinuation = nil
                return
            }
            self.discoveryContinuation?.resume()
            self.discoveryContinuation = nil
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        Task { @MainActor in
            if let error {
                LogManager.shared.log("BLE", "notify 상태 변경 실패: \(error.localizedDescription)")
            } else {
                LogManager.shared.log("BLE", "notify 상태 변경: uuid=\(characteristic.uuid.uuidString) isNotifying=\(characteristic.isNotifying)")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        if let error {
            LogManager.shared.log("BLE", "notify 수신 에러: \(error.localizedDescription)")
            return
        }
        guard let value = characteristic.value else {
            LogManager.shared.log("BLE", "notify 수신 빈 value")
            return
        }
        let bytes = [UInt8](value)
        Task { @MainActor [weak self] in
            guard let self else { return }
            LogManager.shared.log("BLE", "notify 수신 \(bytes.count)B: \(self.hex(bytes)) waiting=\(self.frameContinuation != nil)")
            let frames = self.assembler.append(bytes)
            if frames.isEmpty {
                LogManager.shared.log("BLE", "조립기: 미완성 프레임 대기 중")
            }
            for (index, frame) in frames.enumerated() {
                if let c = self.frameContinuation {
                    self.frameContinuation = nil
                    if frames.count > 1 {
                        LogManager.shared.log("BLE", "조립기: \(frames.count)개 프레임 중 \(index)번 사용, 나머지 \(frames.count - 1)개 버림")
                    }
                    c.resume(returning: frame)
                    break
                } else {
                    LogManager.shared.log("BLE", "notify 프레임 버림 (\(frame.count)B, continuation 없음): \(self.hex(frame))")
                }
            }
        }
    }
}
