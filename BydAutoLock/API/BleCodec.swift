import Foundation

/// BYD 차량 BLE 다이렉트 제어 프레임 코덱 (한국 dkey 경로에서 검증된 PoC 기준).
/// Android `BydBleCodec.java` + `BleRandomExchangeResult.java` 포팅
/// (참고: PoorGrammerA/BydBleAutoLock, MIT License).
///
/// **원본과의 차이**: Java 원본은 세션 키(`appRandom`/`sessionIv`/`aesKey`/`cmacKey`)를 `static`으로 들고 있어
/// 프로세스 전체가 하나의 세션만 가정한다. 이 포팅에서는 인스턴스 프로퍼티로 바꿔서, 인증 세션마다 별도
/// `BleCodec` 인스턴스를 만들면 동시 재시도·재연결 시 상태가 서로 오염되지 않는다
/// (`tasks/ble_direct_control_plan.md` Phase 3 참고).
final class BleCodec {

    static let serviceUUID = "42594420-4155-544F-E0A9-E50E24DCCA9E"
    static let sendCharacteristicUUID = "42590002-4155-544F-E0A9-E50E24DCCA9E"
    static let receiveCharacteristicUUID = "42590003-4155-544F-E0A9-E50E24DCCA9E"

    static let responseControl: UInt8 = 0x24
    static let responseRandomExchange: UInt8 = 0x2A
    static let responseAuthentication: UInt8 = 0x2B
    static let controlCommandType: UInt8 = 0xE5

    private var sequence: UInt16 = 0
    private var appRandom = [UInt8](repeating: 0, count: 8)
    private var sessionIv = [UInt8](repeating: 0, count: 16)
    private var aesKey = [UInt8](repeating: 0, count: 16)
    private var cmacKey = [UInt8](repeating: 0, count: 16)

    init() {}

    func clearSession() {
        appRandom = [UInt8](repeating: 0, count: 8)
        sessionIv = [UInt8](repeating: 0, count: 16)
        aesKey = [UInt8](repeating: 0, count: 16)
        cmacKey = [UInt8](repeating: 0, count: 16)
        sequence = 0
    }

    // MARK: - Frame creation

    func createWakeUpFrame() -> [UInt8] {
        [0x5A, 0xA5, 0xD5, 0x00, 0x00, 0xF5, 0xFA]
    }

    /// `random`을 생략하면 `BleCrypto.randomBytes(8)`로 새 앱 난수를 만든다.
    func createRandomExchangeFrame(keyNumber: UInt8, random: [UInt8]? = nil) -> [UInt8] {
        let random = random ?? BleCrypto.randomBytes(8)
        precondition(random.count == 8, "App random must be 8 bytes")

        var frame = [UInt8](repeating: 0, count: 20)
        frame[0] = 0x5A
        frame[1] = 0xA5
        frame[2] = 0xD6
        appRandom = random
        for i in 0..<8 { frame[3 + i] = random[i] }
        frame[11] = keyNumber
        for i in 12..<17 { frame[i] = 0xFF }
        finishCrcFrame(&frame)
        return frame
    }

    /// 차량의 난수 교환 응답을 파싱하고, 성공 시 `sessionIv`를 갱신한다 (실패 시 `nil`).
    /// - Important: 반드시 이 인스턴스의 `createRandomExchangeFrame`으로 만든 `appRandom`이 먼저 설정돼 있어야 한다.
    @discardableResult
    func parseRandomExchange(_ payload: [UInt8]) -> BleRandomExchangeResult? {
        guard payload.count >= 12, payload[0] == Self.responseRandomExchange, payload[1] == 0xD6 else {
            return nil
        }
        let vehicleRandom = Array(payload[3..<11])
        var nextSessionIv = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { nextSessionIv[i] = vehicleRandom[i] }
        for i in 0..<8 { nextSessionIv[8 + i] = appRandom[i] }
        sessionIv = nextSessionIv
        return BleRandomExchangeResult(
            valid: true,
            vehicleRandom: vehicleRandom,
            crcCheckResult: payload[11],
            keyState: payload[2]
        )
    }

    /// dkey + 현재 `sessionIv`로 세션 키(aesKey/cmacKey)를 파생하고, 인증 프레임을 만든다.
    /// `parseRandomExchange`가 먼저 성공해서 `sessionIv`가 설정돼 있어야 한다.
    func createAuthenticationFrame(dkey: String) throws -> [UInt8] {
        let dkeyBytes = try Self.decodeHexDkey(dkey.trimmingCharacters(in: .whitespaces))
        var keyMaterial = dkeyBytes
        keyMaterial.append(contentsOf: sessionIv)
        let digest = BleCrypto.sha256(keyMaterial)
        aesKey = Array(digest[0..<16])
        cmacKey = Array(digest[16..<32])

        var plain = [UInt8](repeating: 0, count: 16)
        plain[0] = 0xD8
        for i in 1..<12 { plain[i] = 0xFF }
        let mac = try BleCrypto.aesCmac(key: cmacKey, input: plain, length: 12)
        for i in 0..<4 { plain[12 + i] = mac[i] }
        return try wrapEncrypted(plain)
    }

    static func isValidDkey(_ dkey: String?) -> Bool {
        guard let dkey, !dkey.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let bytes = try? decodeHexDkey(dkey.trimmingCharacters(in: .whitespaces)) else { return false }
        return !bytes.isEmpty
    }

    /// 인증 완료(`createAuthenticationFrame` 성공) 후에만 호출 — `cmacKey`/`aesKey`가 세팅돼 있어야 한다.
    func createControlFrame(controlCode: UInt8) throws -> [UInt8] {
        var plain = [UInt8](repeating: 0, count: 16)
        plain[0] = Self.controlCommandType
        plain[1] = controlCode
        sequence = sequence == 0xFFFF ? 1 : sequence + 1
        plain[2] = UInt8(sequence >> 8)
        plain[3] = UInt8(sequence & 0xFF)
        for i in 4..<12 { plain[i] = 0xFF }
        if controlCode == 0x03 { plain[4] = 0x00 }
        let mac = try BleCrypto.aesCmac(key: cmacKey, input: plain, length: 12)
        for i in 0..<4 { plain[12 + i] = mac[i] }
        return try wrapEncrypted(plain)
    }

    // MARK: - Response parsing

    static func parseAuthenticationResult(_ payload: [UInt8]) -> UInt8 {
        guard payload.count >= 3, payload[0] == responseAuthentication, payload[1] == 0xD8 else { return 0xFF }
        return payload[2]
    }

    static func parseResponseType(_ payload: [UInt8]) -> Int {
        payload.isEmpty ? -1 : Int(payload[0])
    }

    static func parseResponseCommandType(_ payload: [UInt8]) -> Int {
        payload.count > 1 ? Int(payload[1]) : -1
    }

    static func parseControlCode(_ payload: [UInt8]) -> Int {
        payload.count > 2 ? Int(payload[2]) : -1
    }

    static func parseControlResult(_ payload: [UInt8]) -> Int {
        payload.count > 3 ? Int(payload[3]) : -1
    }

    static func parseDoorStates(_ payload: [UInt8]) -> Int {
        payload.count > 4 ? Int(payload[4]) : -1
    }

    /// functionId → 차량 제어 코드. 지원하지 않는 functionId는 `0xFF`.
    static func getControlCode(_ functionId: Int) -> UInt8 {
        switch functionId {
        case 9001: return 0x05   // 잠금해제
        case 9002: return 0x07   // 잠금
        case 9003: return 0x03   // 공조 시작
        case 9005: return 0x0A   // 라이트+경적 (차량찾기)
        case 9007: return 0x0C   // 창문 닫기
        case 9009: return 0x08   // 공조 정지
        case 9010: return 0x16   // 라이트만
        case 9011, 9015: return 0x06  // 트렁크 열기/제어
        case 9019: return 0x1A
        case 9020: return 0x18
        case -1:   return 0x19
        default:   return 0xFF
        }
    }

    // MARK: - Private

    private func wrapEncrypted(_ plain: [UInt8]) throws -> [UInt8] {
        let encrypted = try BleCrypto.aesCbcEncryptNoPadding(plain, key: aesKey, iv: sessionIv)
        var frame = [UInt8](repeating: 0, count: 20)
        frame[0] = 0x5B
        frame[1] = 0xB5
        for i in 0..<16 { frame[2 + i] = encrypted[i] }
        frame[18] = 0xF5
        frame[19] = 0xFA
        return frame
    }

    private func finishCrcFrame(_ frame: inout [UInt8]) {
        frame[17] = BleCrypto.crc8(frame, offset: 0, endInclusive: 16)
        frame[18] = 0xF5
        frame[19] = 0xFA
    }

    private static func decodeHexDkey(_ value: String) throws -> [UInt8] {
        guard value.count % 2 == 0, value.count <= 64 else {
            throw BleCodecError.invalidDkey
        }
        var output = [UInt8]()
        output.reserveCapacity(value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else {
                throw BleCodecError.invalidDkey
            }
            output.append(byte)
            index = next
        }
        return output
    }
}

/// 차량/앱 난수 교환 결과.
struct BleRandomExchangeResult {
    let valid: Bool
    let vehicleRandom: [UInt8]
    let crcCheckResult: UInt8
    let keyState: UInt8
}

enum BleCodecError: Error {
    case invalidDkey
}
