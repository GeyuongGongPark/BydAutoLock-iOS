import Foundation
import CommonCrypto
import CryptoKit

enum CryptoUtils {

    // MARK: - MD5

    static func md5Hex(_ value: String) -> String {
        let data = Data(value.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func pwdLoginKey(_ password: String) -> String {
        return md5Hex(md5Hex(password))
    }

    // MARK: - SHA1 Mixed

    static func sha1Mixed(_ value: String) -> String {
        let data = Data(value.utf8)
        let digest = Insecure.SHA1.hash(data: data)
        let bytes = Array(digest)

        // 홀수 인덱스 대문자, 짝수 인덱스 소문자 혼합
        var mixed = ""
        for (i, byte) in bytes.enumerated() {
            let hex = String(format: "%02x", byte)
            mixed += i % 2 == 0 ? hex.uppercased() : hex.lowercased()
        }

        // 짝수 위치의 '0' 제거
        var filtered = ""
        for (j, ch) in mixed.enumerated() {
            if ch == "0" && j % 2 == 0 { continue }
            filtered.append(ch)
        }
        return filtered
    }

    // MARK: - Checkcode

    static func computeCheckcode(_ jsonStr: String) -> String {
        let md5 = md5Hex(jsonStr).lowercased()
        let s = md5.startIndex
        func sub(_ from: Int, _ to: Int) -> String {
            let start = md5.index(s, offsetBy: from)
            let end   = md5.index(s, offsetBy: to)
            return String(md5[start..<end])
        }
        return sub(24, 32) + sub(8, 16) + sub(16, 24) + sub(0, 8)
    }

    // MARK: - AES-128-CBC (Standard, Zero IV, PKCS7)

    static func aesEncryptHex(_ plaintext: String, keyHex: String) -> String {
        let keyBytes = hexToBytes(keyHex)
        let iv = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        guard let encrypted = aesCrypt(.encrypt, data: Data(plaintext.utf8), key: keyBytes, iv: iv) else { return "" }
        return encrypted.map { String(format: "%02X", $0) }.joined()
    }

    static func aesDecryptUTF8(_ cipherHex: String, keyHex: String) -> String {
        let keyBytes = hexToBytes(keyHex)
        let cipherData = Data(hexToBytes(cipherHex))
        let iv = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        guard let decrypted = aesCrypt(.decrypt, data: cipherData, key: keyBytes, iv: iv) else { return "" }
        return String(data: decrypted, encoding: .utf8) ?? ""
    }

    private enum AESOperation { case encrypt, decrypt }

    private static func aesCrypt(_ op: AESOperation, data: Data, key: [UInt8], iv: [UInt8]) -> Data? {
        let operation = op == .encrypt ? CCOperation(kCCEncrypt) : CCOperation(kCCDecrypt)
        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var numBytes = 0

        let status: CCCryptorStatus = buffer.withUnsafeMutableBytes { bufPtr in
            data.withUnsafeBytes { dataPtr in
                iv.withUnsafeBytes { ivPtr in
                    key.withUnsafeBytes { keyPtr in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            dataPtr.baseAddress, data.count,
                            bufPtr.baseAddress, bufferSize,
                            &numBytes
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        buffer.count = numBytes
        return buffer
    }

    // MARK: - Sign String

    static func buildSignString(_ fields: [String: String], password: String) -> String {
        let pairs = fields.sorted { $0.key < $1.key }
                         .map { "\($0.key)=\($0.value)" }
                         .joined(separator: "&")
        return pairs + "&password=\(password)"
    }

    // MARK: - Hex Utilities

    static func hexToBytes(_ hex: String) -> [UInt8] {
        let s = hex.lowercased()
        var bytes = [UInt8]()
        bytes.reserveCapacity(s.count / 2)
        var i = s.startIndex
        while i < s.endIndex {
            let next = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
            if let byte = UInt8(s[i..<next], radix: 16) { bytes.append(byte) }
            i = next
        }
        return bytes
    }

    static func bytesToHex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
