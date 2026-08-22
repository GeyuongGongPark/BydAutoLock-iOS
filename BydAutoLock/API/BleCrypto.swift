import Foundation
import CommonCrypto
import CryptoKit
import Security

/// BYD 차량 BLE 다이렉트 제어 프로토콜(한국 dkey 경로)에 쓰이는 암호화 프리미티브.
/// Android BydBleCrypto.java를 Swift로 포팅 (참고: PoorGrammerA/BydBleAutoLock, MIT License).
///
/// `CryptoUtils`(서버 REST API용, 헥스 문자열 기반)와는 완전히 별도다 — 이 코덱은 원시 바이트 배열([UInt8])을
/// 직접 다루고 AES-CMAC처럼 REST 쪽에 없던 프리미티브가 필요하기 때문에 파일을 나눴다.
enum BleCrypto {

    private static let crc8Polynomial: UInt8 = 0x07

    /// CRC-8 (polynomial 0x07). `offset`부터 `endInclusive`까지 양끝 포함 구간을 계산한다.
    static func crc8(_ data: [UInt8], offset: Int, endInclusive: Int) -> UInt8 {
        guard offset >= 0, endInclusive >= offset, endInclusive < data.count else { return 0 }
        var crc: UInt8 = 0
        for i in offset...endInclusive {
            crc ^= data[i]
            for _ in 0..<8 {
                crc = (crc & 0x80) != 0 ? (crc << 1) ^ crc8Polynomial : (crc << 1)
            }
        }
        return crc
    }

    /// 암호학적으로 안전한 난수 (Android `SecureRandom`과 동등한 `SecRandomCopyBytes` 사용).
    static func randomBytes(_ length: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status)")
        return bytes
    }

    static func sha256(_ input: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: Data(input)))
    }

    /// AES/CBC/NoPadding. `input`은 반드시 16바이트의 배수여야 한다 (이 코덱에서는 항상 정확히 16바이트).
    static func aesCbcEncryptNoPadding(_ input: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        try aesCrypt(input, key: key, iv: iv, options: 0)
    }

    /// RFC 4493 AES-CMAC. `length`(<= input.count)까지만 MAC 대상으로 삼는다 — 호출부가 16바이트 버퍼 중
    /// 앞 12바이트만 서명하는 식으로 쓰기 때문 (마지막 4바이트는 MAC 결과를 담는 자리).
    static func aesCmac(key: [UInt8], input: [UInt8], length: Int) throws -> [UInt8] {
        guard key.count == 16, length >= 0, length <= input.count else {
            throw BleCryptoError.invalidInput
        }
        let l = try aesEcbEncrypt([UInt8](repeating: 0, count: 16), key: key)
        var k1 = leftShift(l)
        if (l[0] & 0x80) != 0 { k1[15] ^= 0x87 }
        var k2 = leftShift(k1)
        if (k1[0] & 0x80) != 0 { k2[15] ^= 0x87 }

        let blocks = max(1, (length + 15) / 16)
        let complete = length > 0 && length % 16 == 0
        var last = [UInt8](repeating: 0, count: 16)
        let lastStart = (blocks - 1) * 16

        if complete {
            last = Array(input[lastStart..<(lastStart + 16)])
            xorInPlace(&last, k1)
        } else {
            let remaining = length - lastStart
            if remaining > 0 {
                for i in 0..<remaining { last[i] = input[lastStart + i] }
            }
            last[remaining] = 0x80
            xorInPlace(&last, k2)
        }

        var state = [UInt8](repeating: 0, count: 16)
        for block in 0..<(blocks - 1) {
            var value = Array(input[(block * 16)..<(block * 16 + 16)])
            xorInPlace(&value, state)
            state = try aesEcbEncrypt(value, key: key)
        }
        xorInPlace(&last, state)
        return try aesEcbEncrypt(last, key: key)
    }

    // MARK: - Private

    private static func aesEcbEncrypt(_ input: [UInt8], key: [UInt8]) throws -> [UInt8] {
        try aesCrypt(input, key: key, iv: nil, options: CCOptions(kCCOptionECBMode))
    }

    private static func aesCrypt(_ input: [UInt8], key: [UInt8], iv: [UInt8]?, options: CCOptions) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var outputCount = 0

        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outPtr in
            input.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    if let iv {
                        return iv.withUnsafeBytes { ivPtr in
                            CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES128), options,
                                    keyPtr.baseAddress, key.count, ivPtr.baseAddress,
                                    inPtr.baseAddress, input.count,
                                    outPtr.baseAddress, output.count, &outputCount)
                        }
                    } else {
                        return CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES128), options,
                                       keyPtr.baseAddress, key.count, nil,
                                       inPtr.baseAddress, input.count,
                                       outPtr.baseAddress, output.count, &outputCount)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw BleCryptoError.aesFailed }
        return Array(output.prefix(outputCount))
    }

    private static func leftShift(_ input: [UInt8]) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: 16)
        var carry: UInt8 = 0
        for i in stride(from: 15, through: 0, by: -1) {
            let value = input[i]
            output[i] = (value << 1) | carry
            carry = value >> 7
        }
        return output
    }

    private static func xorInPlace(_ target: inout [UInt8], _ value: [UInt8]) {
        for i in 0..<target.count { target[i] ^= value[i] }
    }
}

enum BleCryptoError: Error {
    case invalidInput
    case aesFailed
}
