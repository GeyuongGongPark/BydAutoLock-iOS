import XCTest
@testable import BydAutoLock

/// 원본(Android) `BydPureJavaCodecTest.java`의 크립토 관련 검증 벡터를 그대로 이식.
/// 값은 원본 저장소(PoorGrammerA/BydBleAutoLock) 테스트 소스에서 그대로 복사 — 임의로 손으로 계산하지 않았음.
final class BleCryptoTests: XCTestCase {

    /// RFC 4493 AES-CMAC 표준 벡터 (key=2B7E151628AED2A6ABF7158809CF4F3C, 빈 메시지).
    func testAesCmacMatchesRfc4493Vector() throws {
        let key = CryptoUtils.hexToBytes("2B7E151628AED2A6ABF7158809CF4F3C")
        let expected = CryptoUtils.hexToBytes("BB1D6929E95937287FA37D129B756746")

        let mac = try BleCrypto.aesCmac(key: key, input: [], length: 0)

        XCTAssertEqual(mac, expected)
    }

    /// crc8(data, 0, 16)이 양끝 포함(inclusive) 구간이라는 계약을 확인 — 원본 주석: "byte 17 is filled with the expected CRC below".
    func testCrc8UsesInclusiveEndIndexContract() {
        let captured = CryptoUtils.hexToBytes("5AA5D6010203040506070805FFFFFFFFFF6AF5FA")

        XCTAssertEqual(BleCrypto.crc8(captured, offset: 0, endInclusive: 16), 0x6A)
        XCTAssertEqual(captured[17], BleCrypto.crc8(captured, offset: 0, endInclusive: 16))
    }
}
