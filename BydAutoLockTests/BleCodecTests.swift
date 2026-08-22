import XCTest
@testable import BydAutoLock

/// 원본(Android) `BydBleCodecVectorTest.java` + `BydPureJavaCodecTest.java`의 검증 벡터를 그대로 이식.
/// 모든 hex 값은 원본 저장소(PoorGrammerA/BydBleAutoLock) 테스트 소스에서 그대로 복사했다 — 손으로 계산한 값 없음.
///
/// 원본은 `BydBleCodec`의 세션 상태가 static(프로세스 전역)이라 테스트 실행 순서에 암묵적으로 의존하지만,
/// 이 포팅은 세션 상태를 인스턴스 프로퍼티로 바꿔서 각 테스트가 자기만의 `BleCodec()`을 쓴다 — 더 안전한 격리.
final class BleCodecTests: XCTestCase {

    /// wake→random exchange→dkey 인증까지 이어지는 한 세션의 전체 와이어 벡터.
    func testAuthenticationFrameMatchesKnownWireVector() throws {
        let codec = BleCodec()
        let appRandom = CryptoUtils.hexToBytes("1020304050607080")

        let randomFrame = codec.createRandomExchangeFrame(keyNumber: 0, random: appRandom)
        XCTAssertEqual(randomFrame, CryptoUtils.hexToBytes("5AA5D6102030405060708000FFFFFFFFFF3CF5FA"))

        let responsePayload = CryptoUtils.hexToBytes("2AD601112233445566778801FFFFFFFF")
        XCTAssertNotNil(codec.parseRandomExchange(responsePayload))

        let auth = try codec.createAuthenticationFrame(dkey: "00112233445566778899AABBCCDDEEFF")
        XCTAssertEqual(auth, CryptoUtils.hexToBytes("5BB50396C4727C202D50B06A0477CF412BEBF5FA"))
    }

    func testWakeAndRandomFramesHaveConfirmedWireShape() {
        let codec = BleCodec()
        XCTAssertEqual(codec.createWakeUpFrame(), CryptoUtils.hexToBytes("5AA5D50000F5FA"))

        let frame = codec.createRandomExchangeFrame(keyNumber: 3)
        XCTAssertEqual(frame.count, 20)
        XCTAssertEqual(frame[0], 0x5A)
        XCTAssertEqual(frame[1], 0xA5)
        XCTAssertEqual(frame[2], 0xD6)
        XCTAssertEqual(frame[11], 3)
        XCTAssertEqual(frame[17], BleCrypto.crc8(frame, offset: 0, endInclusive: 16))
        XCTAssertEqual(frame[18], 0xF5)
        XCTAssertEqual(frame[19], 0xFA)
    }

    func testDkeyAuthenticationAndControlUseEncrypted5bB5Envelope() throws {
        XCTAssertTrue(BleCodec.isValidDkey("0123456789abcdef0123456789abcdef"))
        XCTAssertFalse(BleCodec.isValidDkey("not-a-key"))

        let codec = BleCodec()
        let auth = try codec.createAuthenticationFrame(dkey: "0123456789abcdef0123456789abcdef")
        assertEncryptedEnvelope(auth)

        let control = try codec.createControlFrame(controlCode: 0x05)
        assertEncryptedEnvelope(control)

        XCTAssertNotEqual(auth, control)
    }

    func testParsesNewKeyRandomResponse() {
        let codec = BleCodec()
        let response = CryptoUtils.hexToBytes("2AD601102030405060708001000000000000F5FA")

        XCTAssertEqual(BleCodec.parseResponseType(response), 0x2A)

        let parsed = codec.parseRandomExchange(response)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.valid, true)
        XCTAssertEqual(parsed?.keyState, 1)
        XCTAssertEqual(parsed?.crcCheckResult, 1)
        XCTAssertEqual(parsed?.vehicleRandom, CryptoUtils.hexToBytes("1020304050607080"))
    }

    func testFunctionIdsMatchDocumentedMap() {
        XCTAssertEqual(BleCodec.getControlCode(9001), 0x05)
        XCTAssertEqual(BleCodec.getControlCode(9002), 0x07)
        XCTAssertEqual(BleCodec.getControlCode(9003), 0x03)
        XCTAssertEqual(BleCodec.getControlCode(9005), 0x0A)
        XCTAssertEqual(BleCodec.getControlCode(9007), 0x0C)
        XCTAssertEqual(BleCodec.getControlCode(9010), 0x16)
        XCTAssertEqual(BleCodec.getControlCode(9011), 0x06)
        XCTAssertEqual(BleCodec.getControlCode(9015), 0x06)
        XCTAssertEqual(BleCodec.getControlCode(9019), 0x1A)
        XCTAssertEqual(BleCodec.getControlCode(9020), 0x18)
        XCTAssertEqual(BleCodec.getControlCode(9004), 0xFF)
    }

    func testParsesVehicleControlAcknowledgementFields() {
        var response = [UInt8](repeating: 0xFF, count: 16)
        response[0] = BleCodec.responseControl
        response[1] = BleCodec.controlCommandType
        response[2] = BleCodec.getControlCode(9002)
        response[3] = 0x01
        response[4] = 0xC0

        XCTAssertEqual(BleCodec.parseResponseType(response), 0x24)
        XCTAssertEqual(BleCodec.parseResponseCommandType(response), 0xE5)
        XCTAssertEqual(BleCodec.parseControlCode(response), 0x07)
        XCTAssertEqual(BleCodec.parseControlResult(response), 0x01)
        XCTAssertEqual(BleCodec.parseDoorStates(response), 0xC0)
    }

    func testGattUuidsMatchVehicleServiceDiscoveryCapture() {
        XCTAssertEqual(BleCodec.serviceUUID, "42594420-4155-544F-E0A9-E50E24DCCA9E")
        XCTAssertEqual(BleCodec.sendCharacteristicUUID, "42590002-4155-544F-E0A9-E50E24DCCA9E")
        XCTAssertEqual(BleCodec.receiveCharacteristicUUID, "42590003-4155-544F-E0A9-E50E24DCCA9E")
    }

    private func assertEncryptedEnvelope(_ frame: [UInt8]) {
        XCTAssertEqual(frame.count, 20)
        XCTAssertEqual(frame[0], 0x5B)
        XCTAssertEqual(frame[1], 0xB5)
        XCTAssertEqual(frame[18], 0xF5)
        XCTAssertEqual(frame[19], 0xFA)
    }
}
