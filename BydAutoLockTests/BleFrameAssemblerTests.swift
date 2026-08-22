import XCTest
import Foundation
@testable import BydAutoLock

final class BleFrameAssemblerTests: XCTestCase {

    /// wake 프레임 하나가 정확히 한 번의 notify로 도착하는 정상 케이스.
    func testSingleCompleteFrameInOneNotify() {
        let assembler = BleFrameAssembler()
        let frame = CryptoUtils.hexToBytes("5AA5D50000F5FA")

        let result = assembler.append(frame)

        XCTAssertEqual(result, [frame])
    }

    /// 두 프레임이 한 notify에 이어붙어서 온 경우 — 도착 순서대로 둘 다 잘라내야 한다.
    func testTwoFramesConcatenatedInOneNotify() {
        let assembler = BleFrameAssembler()
        let frame1 = CryptoUtils.hexToBytes("5AA5D50000F5FA")
        let frame2 = CryptoUtils.hexToBytes("5AA5D6102030405060708000FFFFFFFFFF3CF5FA")

        let result = assembler.append(frame1 + frame2)

        XCTAssertEqual(result, [frame1, frame2])
    }

    /// 한 프레임이 두 번의 notify로 쪼개져서 오는 경우 — 첫 조각만으로는 완성된 프레임이 없어야 하고,
    /// 나머지가 도착하면 그때 온전한 프레임 하나가 나와야 한다.
    func testFrameSplitAcrossTwoNotifies() {
        let assembler = BleFrameAssembler()
        let frame = CryptoUtils.hexToBytes("5AA5D6102030405060708000FFFFFFFFFF3CF5FA")
        let firstHalf = Array(frame[0..<10])
        let secondHalf = Array(frame[10...])

        let resultAfterFirst = assembler.append(firstHalf)
        XCTAssertEqual(resultAfterFirst, [])

        let resultAfterSecond = assembler.append(secondHalf)
        XCTAssertEqual(resultAfterSecond, [frame])
    }

    /// 다음 프레임의 앞부분이 먼저 도착해도, 완성되기 전까지는 버퍼에 남아있어야 한다 (유실 없음).
    func testLeftoverBytesArePreservedForNextFrame() {
        let assembler = BleFrameAssembler()
        let frame1 = CryptoUtils.hexToBytes("5AA5D50000F5FA")
        let frame2 = CryptoUtils.hexToBytes("5AA5D6102030405060708000FFFFFFFFFF3CF5FA")
        let frame2FirstHalf = Array(frame2[0..<5])
        let frame2SecondHalf = Array(frame2[5...])

        let result1 = assembler.append(frame1 + frame2FirstHalf)
        XCTAssertEqual(result1, [frame1])

        let result2 = assembler.append(frame2SecondHalf)
        XCTAssertEqual(result2, [frame2])
    }

    /// 종단 마커를 계속 못 찾는 오염된 데이터가 상한을 넘으면 버퍼를 비워서 무한정 쌓이지 않게 한다.
    func testOverflowingGarbageResetsBuffer() {
        let assembler = BleFrameAssembler()
        let garbage = [UInt8](repeating: 0x00, count: 500)

        let result = assembler.append(garbage)
        XCTAssertEqual(result, [])

        // 버퍼가 비워졌으므로, 이후 정상 프레임은 새로 깨끗하게 인식되어야 한다.
        let frame = CryptoUtils.hexToBytes("5AA5D50000F5FA")
        let result2 = assembler.append(frame)
        XCTAssertEqual(result2, [frame])
    }

    /// `reset()`이 이전에 쌓아둔(마커 없는) 조각을 실제로 버리는지 확인.
    /// reset이 제대로 안 됐다면, 이 조각 뒤에 오는 완전한 프레임과 합쳐져서 그 프레임 앞에 5바이트가
    /// 더 붙은 "잘못된 프레임"이 나온다 — 그 오염을 잡아내는 테스트.
    func testResetDropsBufferedPartialFrame() {
        let assembler = BleFrameAssembler()
        let frame2 = CryptoUtils.hexToBytes("5AA5D6102030405060708000FFFFFFFFFF3CF5FA")
        let partialNoMarker = Array(frame2[0..<5])  // F5FA를 포함하지 않는, 완성되지 않은 조각
        _ = assembler.append(partialNoMarker)

        assembler.reset()

        let frame1 = CryptoUtils.hexToBytes("5AA5D50000F5FA")
        let result = assembler.append(frame1)
        XCTAssertEqual(result, [frame1])
    }

    func testDataOverloadMatchesByteArrayOverload() {
        let assembler = BleFrameAssembler()
        let frame = CryptoUtils.hexToBytes("5AA5D50000F5FA")

        let result = assembler.append(Data(frame))

        XCTAssertEqual(result, [frame])
    }
}
