import XCTest
@testable import BydAutoLock

final class CryptoUtilsTests: XCTestCase {

    func testMd5HexReturnsUppercaseDigest() {
        XCTAssertEqual(CryptoUtils.md5Hex("abc"), "900150983CD24FB0D6963F7D28E17F72")
    }

    func testPasswordLoginKeyHashesMd5DigestAgain() {
        XCTAssertEqual(CryptoUtils.pwdLoginKey("password"), "3B73CCA8B7D9D93A834631FB22769334")
    }

    func testSha1MixedAppliesCaseMixingAndZeroFiltering() {
        XCTAssertEqual(CryptoUtils.sha1Mixed("abc"), "A9993E36476816aBA3e25717850C26c9Cd0D89d")
    }

    func testComputeCheckcodeReordersMd5Segments() {
        XCTAssertEqual(CryptoUtils.computeCheckcode("{\"a\":1}"), "a366f2d88df4652941caf652bb6cb5c6")
    }

    func testHexConversionHandlesUppercaseLowercaseAndOddLength() {
        XCTAssertEqual(CryptoUtils.hexToBytes("0A1bF"), [0x0A, 0x1B, 0x0F])
        XCTAssertEqual(CryptoUtils.bytesToHex([0x00, 0x0A, 0xFF]), "000aff")
    }

    func testAesEncryptsWithZeroIvAndPkcs7Padding() throws {
        let key = "000102030405060708090A0B0C0D0E0F"

        let cipherHex = try CryptoUtils.aesEncryptHex("hello", keyHex: key)

        XCTAssertEqual(cipherHex, "5D8749E2AF7531B2BF6661E9E5DAF012")
        XCTAssertEqual(try CryptoUtils.aesDecryptUTF8(cipherHex, keyHex: key), "hello")
    }
}
