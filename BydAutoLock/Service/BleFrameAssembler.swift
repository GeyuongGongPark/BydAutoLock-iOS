import Foundation

/// BLE notify로 들어오는 바이트 스트림에서 완성된 응답 프레임을 잘라내는 조립기.
///
/// CoreBluetooth의 GATT notify는 기본적으로 "한 번의 `didUpdateValueFor` 콜백 = 그 순간 보낸 값 전체"라서,
/// 대부분은 이 조립기 없이 `characteristic.value`를 그대로 `BleCodec`의 파싱 함수에 넘겨도 될 가능성이 높다.
/// 이 클래스는 그 가정이 실기기에서 깨지는 두 경우를 대비한 방어 계층이다:
/// - 여러 응답 프레임이 한 notify에 이어 붙어서 오는 경우
/// - 한 프레임이 두 번 이상의 notify로 쪼개져서 오는 경우
///
/// 프레임 경계는 앱이 보내는 프레임과 동일한 `F5 FA` 종단 마커로 찾는다. `BydBleCodec`가 실제로 검증하는
/// 필드(첫 2바이트 type, 특정 인덱스 값)와는 무관하게, 이 클래스는 순수히 "어디까지가 한 프레임인지"만 잘라낸다.
///
/// - Important: 차량 응답이 정말 매번 `F5 FA`로 끝나는지는 실기기로 확인되지 않았다 — 원본 저장소의 테스트
///   벡터 중 일부(예: `parseRandomExchange` 테스트용 16바이트 synthetic payload)에는 이 마커가 없다.
///   이건 그 유닛 테스트가 파싱 함수의 관용성만 확인하려고 일부러 잘라 만든 값이라 실제 와이어 캡처가
///   아니었을 수 있다 — Phase 8 실기기 로그로 이 가정을 재확인해야 한다 (`tasks/ble_direct_control_plan.md`).
final class BleFrameAssembler {

    /// 이 이상 쌓였는데도 종단 마커를 못 찾으면 오염된 것으로 보고 버퍼를 비운다 (무한정 누적 방지).
    private static let maxBufferedBytes = 200

    private var buffer: [UInt8] = []

    /// 새로 도착한 notify 데이터를 버퍼에 추가하고, 그 시점까지 잘라낼 수 있는 완성된 프레임들을
    /// 도착 순서대로 반환한다. 아직 완성되지 않은 나머지는 버퍼에 남아 다음 호출에 이어진다.
    @discardableResult
    func append(_ data: [UInt8]) -> [[UInt8]] {
        buffer.append(contentsOf: data)

        var frames: [[UInt8]] = []
        while let tailEnd = firstTailMarkerEnd() {
            frames.append(Array(buffer[0..<tailEnd]))
            buffer.removeFirst(tailEnd)
        }

        if buffer.count > Self.maxBufferedBytes {
            buffer.removeAll()
        }
        return frames
    }

    @discardableResult
    func append(_ data: Data) -> [[UInt8]] {
        append([UInt8](data))
    }

    /// 재연결 등으로 세션이 끊길 때 남은 조각을 버려서 다음 세션에 잘못 이어붙지 않게 한다.
    func reset() {
        buffer.removeAll()
    }

    /// `F5 FA` 두 바이트가 끝나는 지점(그 다음 인덱스, 즉 `buffer[0..<end]`가 마커까지 포함하는 상한)을 찾는다.
    private func firstTailMarkerEnd() -> Int? {
        guard buffer.count >= 2 else { return nil }
        for i in 0..<(buffer.count - 1) {
            if buffer[i] == 0xF5 && buffer[i + 1] == 0xFA {
                return i + 2
            }
        }
        return nil
    }
}
