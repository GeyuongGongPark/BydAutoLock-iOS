import XCTest
@testable import BydAutoLock

/// BydWatchKeyService의 순수 로직만 검증 (실 서버 호출 없음) — CryptoUtilsTests와 동일한 스타일.
final class BydWatchKeyServiceTests: XCTestCase {

    private func makeService() -> BydWatchKeyService {
        let config = BydConfig.fromRegion("KR")
        return BydWatchKeyService(config: config, watchImei: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
    }

    /// QR 콘텐츠는 AES-CBC(zero IV)로 암호화되므로, 같은 키로 복호화하면 원래 평문과 정확히 일치해야 한다.
    func testBuildQrCodeContentRoundTrips() async throws {
        let service = makeService()
        let content = try await service.buildQrCodeContent(uuid: "TEST-UUID-1234", watchImei: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")

        XCTAssertTrue(content.hasPrefix("watchQRCode://"))
        let hex = String(content.dropFirst("watchQRCode://".count))

        let qrKeyHex = CryptoUtils.md5Hex("watch.bydautolink")
        let decrypted = try CryptoUtils.aesDecryptUTF8(hex, keyHex: qrKeyHex)

        XCTAssertEqual(decrypted, "watchImei=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&uuid=TEST-UUID-1234&countryCode=KR")
    }

    func testBuildQrCodeContentIsUppercaseHexAfterScheme() async throws {
        let service = makeService()
        let content = try await service.buildQrCodeContent(uuid: "abc", watchImei: "def")
        let hex = String(content.dropFirst("watchQRCode://".count))
        XCTAssertEqual(hex, hex.uppercased())
        XCTAssertTrue(hex.allSatisfy { $0.isHexDigit })
    }

    /// gain/vehicle 응답의 watchBluetoothDto.watchBluetoothInfo 경로에서 dkey/mac/keyNumber를 뽑아내는지 확인.
    func testExtractBleInfoFromVehicleConfigNestedPath() {
        let vehicle: [String: Any] = [
            "watchBluetoothDto": [
                "macAddress": "AA:BB:CC:DD:EE:FF",
                "watchBluetoothInfo": [
                    "dkey": "00112233445566778899AABBCCDDEEFF",
                    "keyNumber": 3
                ]
            ]
        ]
        let result = BydWatchKeyService.extractBleInfo(fromVehicleConfig: vehicle)
        XCTAssertEqual(result.dkey, "00112233445566778899AABBCCDDEEFF")
        XCTAssertEqual(result.mac, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(result.keyNumber, 3)
    }

    /// 일부 지역은 cfVechicle 하위에 중첩되어 온다 — 이 경로도 대응해야 함.
    func testExtractBleInfoFromVehicleConfigCfVechiclePath() {
        let vehicle: [String: Any] = [
            "cfVechicle": [
                "watchBluetoothDto": [
                    "macAddress": "11:22:33:44:55:66",
                    "watchBluetoothInfo": [
                        "dkey": "FFEEDDCCBBAA00112233445566778899",
                        "keyNumber": "7"
                    ]
                ]
            ]
        ]
        let result = BydWatchKeyService.extractBleInfo(fromVehicleConfig: vehicle)
        XCTAssertEqual(result.dkey, "FFEEDDCCBBAA00112233445566778899")
        XCTAssertEqual(result.mac, "11:22:33:44:55:66")
        XCTAssertEqual(result.keyNumber, 7)
    }

    func testExtractBleInfoReturnsNilsWhenDtoMissing() {
        let result = BydWatchKeyService.extractBleInfo(fromVehicleConfig: ["unrelated": "value"])
        XCTAssertNil(result.dkey)
        XCTAssertNil(result.mac)
        XCTAssertNil(result.keyNumber)
    }
}
