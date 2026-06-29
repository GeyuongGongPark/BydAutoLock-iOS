import Foundation

/// BYD 통신에 사용되는 독자 CBC-AES 변형 코덱
/// Java BangcleCodec.java를 Swift로 직접 포팅
final class BangcleCodec {

    private struct Tables {
        let invRound: [UInt8]    // 0x28000 bytes
        let invXor: [UInt8]      // 0x3C000 bytes
        let invFirst: [UInt8]    // 0x1000 bytes
        let round: [UInt8]       // 0x28000 bytes
        let xor: [UInt8]         // 0x3C000 bytes
        let finalTable: [UInt8]  // 0x1000 bytes
        let permDecrypt: [UInt8] // 8 bytes
        let permEncrypt: [UInt8] // 8 bytes
    }

    enum BangcleError: Error {
        case tableFileNotFound
        case badMagic
        case unsupportedVersion(Int)
        case wrongTableCount(Int)
        case invalidPadding
        case invalidEnvelope
        case base64DecodeError
        case utf8DecodeError
    }

    private let tables: Tables

    init() throws {
        guard let url = Bundle.main.url(forResource: "bangcle_tables", withExtension: "bin"),
              let data = try? Data(contentsOf: url) else {
            throw BangcleError.tableFileNotFound
        }
        tables = try BangcleCodec.loadTables(from: [UInt8](data))
    }

    // MARK: - Table Loading

    private static func loadTables(from bytes: [UInt8]) throws -> Tables {
        var offset = 0

        func readU16() throws -> Int {
            guard offset + 2 <= bytes.count else { throw BangcleError.badMagic }
            let v = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2; return v
        }
        func readU32() throws -> Int {
            guard offset + 4 <= bytes.count else { throw BangcleError.badMagic }
            let v = Int(bytes[offset]) | (Int(bytes[offset+1]) << 8) |
                    (Int(bytes[offset+2]) << 16) | (Int(bytes[offset+3]) << 24)
            offset += 4; return v
        }

        let magic = Array(bytes[0..<4])
        guard magic == [0x42, 0x47, 0x54, 0x42] else { throw BangcleError.badMagic }
        offset = 4

        let version = try readU16()
        guard version == 1 else { throw BangcleError.unsupportedVersion(version) }

        let count = try readU16()
        guard count == 8 else { throw BangcleError.wrongTableCount(count) }

        var offsets = [Int](repeating: 0, count: 8)
        var lengths = [Int](repeating: 0, count: 8)
        for i in 0..<8 {
            offsets[i] = try readU32()
            lengths[i] = try readU32()
        }

        func extract(_ i: Int) -> [UInt8] {
            Array(bytes[offsets[i]..<(offsets[i] + lengths[i])])
        }

        return Tables(
            invRound:    extract(0),
            invXor:      extract(1),
            invFirst:    extract(2),
            round:       extract(3),
            xor:         extract(4),
            finalTable:  extract(5),
            permDecrypt: extract(6),
            permEncrypt: extract(7)
        )
    }

    // MARK: - Block Operations

    private func prepareMatrix(_ block: [UInt8]) -> [UInt8] {
        var state = [UInt8](repeating: 0, count: 32)
        for col in 0..<4 {
            for row in 0..<4 {
                state[col * 8 + row] = block[col + row * 4]
            }
        }
        return state
    }

    private func extractBlock(_ state: [UInt8]) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: 16)
        for col in 0..<4 {
            for row in 0..<4 {
                output[col + row * 4] = state[col * 8 + row]
            }
        }
        return output
    }

    private func encryptBlock(_ block: [UInt8], roundEnd: Int) -> [UInt8] {
        var state = prepareMatrix(block)
        var temp64 = [UInt8](repeating: 0, count: 64)
        var tmp32 = [UInt8](repeating: 0, count: 32)

        let rounds = min(9, max(0, roundEnd))

        for rnd in 0..<rounds {
            let lVar21 = rnd * 4
            var permPtr = 0

            for i in 0..<4 {
                let bVar4 = Int(tables.permEncrypt[permPtr]) & 0xFF
                let lVar16 = i * 8
                let base = i * 16

                for j in 0..<4 {
                    let uVar8 = (bVar4 + j) & 3
                    let byteVal = Int(state[lVar16 + uVar8]) & 0xFF
                    let idx = (byteVal + (i + (lVar21 + uVar8) * 4) * 256) * 4
                    temp64[base + j*4]     = tables.round[idx]
                    temp64[base + j*4 + 1] = tables.round[idx + 1]
                    temp64[base + j*4 + 2] = tables.round[idx + 2]
                    temp64[base + j*4 + 3] = tables.round[idx + 3]
                }
                permPtr += 2
            }

            var iVar16 = 1
            for lVar22 in 0..<4 {
                var pbOffset = lVar22
                for lVar10 in 0..<4 {
                    let local10 = Int(temp64[pbOffset]) & 0xFF
                    var uVar7  = local10 & 0xF
                    var uVar26 = local10 & 0xF0
                    let f0 = Int(temp64[pbOffset + 0x10]) & 0xFF
                    let f1 = Int(temp64[pbOffset + 0x20]) & 0xFF
                    let f2 = Int(temp64[pbOffset + 0x30]) & 0xFF
                    let lVar2 = lVar10 * 0x18 + rnd * 0x60
                    var iVar25 = iVar16
                    for lVar17 in 0..<3 {
                        let inner = [f0, f1, f2][lVar17]
                        let uVar1 = (inner << 4) & 0xFF
                        let uVar27 = uVar7 | uVar1
                        uVar26 = ((uVar26 >> 4) | ((inner >> 4) << 4)) & 0xFF
                        uVar7  = Int(tables.xor[(lVar2 + (iVar25 - 1)) * 0x100 + uVar27]) & 0xF
                        let newByte = Int(tables.xor[(lVar2 + iVar25) * 0x100 + uVar26]) & 0xFF
                        uVar26 = (newByte & 0xF) << 4
                        iVar25 += 2
                    }
                    state[lVar10 + lVar22 * 8] = UInt8((uVar26 | uVar7) & 0xFF)
                    pbOffset += 4
                }
                iVar16 += 6
            }
        }

        if roundEnd == 10 {
            tmp32 = Array(state[0..<32])
            for row in 0..<4 {
                state[row]        = tables.finalTable[(Int(tmp32[(0 + row) & 3])     & 0xFF) + ((0 + row) & 3) * 0x400]
                state[8  + row]   = tables.finalTable[(Int(tmp32[8  + ((1 + row) & 3)]) & 0xFF) + ((1 + row) & 3) * 0x400 + 0x100]
                state[0x10 + row] = tables.finalTable[(Int(tmp32[0x10 + ((2 + row) & 3)]) & 0xFF) + ((2 + row) & 3) * 0x400 + 0x200]
                state[0x18 + row] = tables.finalTable[(Int(tmp32[0x18 + ((3 + row) & 3)]) & 0xFF) + ((3 + row) & 3) * 0x400 + 0x300]
            }
        }

        return extractBlock(state)
    }

    private func decryptBlock(_ block: [UInt8], roundStart: Int) -> [UInt8] {
        var state = prepareMatrix(block)
        var temp64 = [UInt8](repeating: 0, count: 64)
        var tmp32 = [UInt8](repeating: 0, count: 32)

        let stopBound = max(0, roundStart)
        for rnd in stride(from: 9, through: stopBound, by: -1) {
            let lVar21 = rnd * 4
            var permPtr = 0

            for i in 0..<4 {
                let bVar3 = Int(tables.permDecrypt[permPtr]) & 0xFF
                let lVar16 = i * 8
                let base = i * 16
                for j in 0..<4 {
                    let uVar7 = (bVar3 + j) & 3
                    let byteVal = Int(state[lVar16 + uVar7]) & 0xFF
                    let idx = (byteVal + (i + (lVar21 + uVar7) * 4) * 256) * 4
                    temp64[base + j*4]     = tables.invRound[idx]
                    temp64[base + j*4 + 1] = tables.invRound[idx + 1]
                    temp64[base + j*4 + 2] = tables.invRound[idx + 2]
                    temp64[base + j*4 + 3] = tables.invRound[idx + 3]
                }
                permPtr += 2
            }

            var iVar15 = 1
            for lVar21x in 0..<4 {
                var pbOffset = lVar21x
                for lVar9 in 0..<4 {
                    let local10 = Int(temp64[pbOffset]) & 0xFF
                    var uVar6  = local10 & 0xF
                    var uVar26 = local10 & 0xF0
                    let f0 = Int(temp64[pbOffset + 0x10]) & 0xFF
                    let f1 = Int(temp64[pbOffset + 0x20]) & 0xFF
                    let f2 = Int(temp64[pbOffset + 0x30]) & 0xFF
                    let lVar2 = lVar9 * 0x18 + rnd * 0x60
                    var iVar25 = iVar15
                    for lVar16 in 0..<3 {
                        let inner = [f0, f1, f2][lVar16]
                        let uVar1 = (inner << 4) & 0xFF
                        let uVar27 = uVar6 | uVar1
                        uVar26 = ((uVar26 >> 4) | ((inner >> 4) << 4)) & 0xFF
                        uVar6  = Int(tables.invXor[(lVar2 + (iVar25 - 1)) * 0x100 + uVar27]) & 0xF
                        let newByte = Int(tables.invXor[(lVar2 + iVar25) * 0x100 + uVar26]) & 0xFF
                        uVar26 = (newByte & 0xF) << 4
                        iVar25 += 2
                    }
                    state[lVar9 + lVar21x * 8] = UInt8((uVar26 | uVar6) & 0xFF)
                    pbOffset += 4
                }
                iVar15 += 6
            }
        }

        if roundStart == 1 {
            tmp32 = Array(state[0..<32])
            var u8 = 1; var u10 = 3; var u12 = 2
            for row in 0..<4 {
                state[row]        = tables.invFirst[(Int(tmp32[row])             & 0xFF) + row * 0x400]
                state[8  + row]   = tables.invFirst[(Int(tmp32[8  + (u10 & 3)]) & 0xFF) + (u10 & 3) * 0x400 + 0x100]
                state[0x10 + row] = tables.invFirst[(Int(tmp32[0x10 + (u12 & 3)]) & 0xFF) + (u12 & 3) * 0x400 + 0x200]
                state[0x18 + row] = tables.invFirst[(Int(tmp32[0x18 + (u8 & 3)])  & 0xFF) + (u8 & 3) * 0x400 + 0x300]
                u8 += 1; u10 += 1; u12 += 1
            }
        }

        return extractBlock(state)
    }

    // MARK: - CBC Mode

    func encryptCBC(data: [UInt8], iv: [UInt8] = [UInt8](repeating: 0, count: 16)) throws -> [UInt8] {
        guard data.count % 16 == 0 else { throw BangcleError.invalidPadding }
        var result = [UInt8](repeating: 0, count: data.count)
        var prev = iv
        for offset in stride(from: 0, to: data.count, by: 16) {
            var block = Array(data[offset..<offset+16])
            for i in 0..<16 { block[i] ^= prev[i] }
            let enc = encryptBlock(block, roundEnd: 10)
            result.replaceSubrange(offset..<offset+16, with: enc)
            prev = enc
        }
        return result
    }

    func decryptCBC(data: [UInt8], iv: [UInt8] = [UInt8](repeating: 0, count: 16)) throws -> [UInt8] {
        guard data.count % 16 == 0 else { throw BangcleError.invalidPadding }
        var result = [UInt8](repeating: 0, count: data.count)
        var prev = iv
        for offset in stride(from: 0, to: data.count, by: 16) {
            let block = Array(data[offset..<offset+16])
            var dec = decryptBlock(block, roundStart: 1)
            for i in 0..<16 { dec[i] ^= prev[i] }
            result.replaceSubrange(offset..<offset+16, with: dec)
            prev = block
        }
        return result
    }

    // MARK: - PKCS7

    private func pkcs7Pad(_ data: [UInt8]) -> [UInt8] {
        let pad = 16 - (data.count % 16)
        return data + [UInt8](repeating: UInt8(pad), count: pad)
    }

    private func pkcs7Unpad(_ data: [UInt8]) throws -> [UInt8] {
        guard let last = data.last, last >= 1, last <= 16, Int(last) <= data.count else {
            throw BangcleError.invalidPadding
        }
        let padLen = Int(last)
        let padStart = data.count - padLen
        guard data[padStart...].allSatisfy({ $0 == last }) else {
            throw BangcleError.invalidPadding
        }
        return Array(data.prefix(padStart))
    }

    // MARK: - Envelope API

    func encodeEnvelope(_ plaintext: String) throws -> String {
        let padded = pkcs7Pad(Array(plaintext.utf8))
        let cipher = try encryptCBC(data: padded)
        return "F" + Data(cipher).base64EncodedString()
    }

    func decodeEnvelope(_ envelope: String) throws -> String {
        var s = envelope
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard s.hasPrefix("F") else { throw BangcleError.invalidEnvelope }
        s = String(s.dropFirst())

        let rem = s.count % 4
        if rem != 0 { s += String(repeating: "=", count: 4 - rem) }

        guard let cipherData = Data(base64Encoded: s) else { throw BangcleError.base64DecodeError }
        let decrypted = try decryptCBC(data: [UInt8](cipherData))
        let unpadded = try pkcs7Unpad(decrypted)
        guard let result = String(bytes: unpadded, encoding: .utf8) else { throw BangcleError.utf8DecodeError }
        return result
    }
}
