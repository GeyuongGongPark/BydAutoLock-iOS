import AppIntents
import Foundation

// MARK: - 공통 헬퍼

/// Intent 실행 시 독립적으로 BydVehicleService를 생성하고 API 호출에 필요한 정보를 반환.
/// 앱이 재시작된 상황에서도 Keychain credentials를 읽어 세션을 복원하거나 재로그인함.
private func makeServiceContext() async throws -> (service: BydVehicleService, vin: String, pin: String) {
    let s = StorageManager.shared
    guard let vin = s.selectedVin, !vin.isEmpty else { throw BydIntentError.notConfigured }
    guard let pin = s.pin,         !pin.isEmpty else { throw BydIntentError.notConfigured }

    let config  = BydConfig.fromRegion(s.region)
    let service = try BydVehicleService(config: config)
    await service.setCredentials(username: s.username ?? "", password: s.password ?? "")
    if let uid = s.userId, let sign = s.signToken, let encry = s.encryToken {
        await service.restoreSession(userId: uid, signToken: sign, encryToken: encry)
    }
    return (service, vin, pin)
}

private enum BydIntentError: LocalizedError {
    case notConfigured
    var errorDescription: String? {
        "BYD AutoLock 앱에서 계정과 차량 설정을 먼저 완료해주세요."
    }
}

// MARK: - Intents

struct LockCarIntent: AppIntent {
    static var title: LocalizedStringResource = "차량 잠금"
    static var description = IntentDescription("BYD 차량을 잠급니다.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (service, vin, pin) = try await makeServiceContext()
        let ok = try await service.lock(vin: vin, pin: pin)
        LogManager.shared.log("API", "Siri 잠금: \(ok ? "성공" : "전송됨")")
        return .result(dialog: ok ? "차량을 잠갔습니다." : "잠금 명령을 전송했습니다.")
    }
}

struct UnlockCarIntent: AppIntent {
    static var title: LocalizedStringResource = "차량 잠금 해제"
    static var description = IntentDescription("BYD 차량 잠금을 해제합니다.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (service, vin, pin) = try await makeServiceContext()
        let ok = try await service.unlock(vin: vin, pin: pin)
        LogManager.shared.log("API", "Siri 잠금 해제: \(ok ? "성공" : "전송됨")")
        return .result(dialog: ok ? "잠금을 해제했습니다." : "잠금 해제 명령을 전송했습니다.")
    }
}

struct OpenTrunkIntent: AppIntent {
    static var title: LocalizedStringResource = "트렁크 열기"
    static var description = IntentDescription("BYD 차량 트렁크를 엽니다.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (service, vin, pin) = try await makeServiceContext()
        let ok = try await service.openTrunk(vin: vin, pin: pin)
        LogManager.shared.log("API", "Siri 트렁크 열기: \(ok ? "성공" : "전송됨")")
        return .result(dialog: ok ? "트렁크를 열었습니다." : "트렁크 열기 명령을 전송했습니다.")
    }
}

struct CloseTrunkIntent: AppIntent {
    static var title: LocalizedStringResource = "트렁크 닫기"
    static var description = IntentDescription("BYD 차량 트렁크를 닫습니다.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (service, vin, pin) = try await makeServiceContext()
        let ok = try await service.closeTrunk(vin: vin, pin: pin)
        LogManager.shared.log("API", "Siri 트렁크 닫기: \(ok ? "성공" : "전송됨")")
        return .result(dialog: ok ? "트렁크를 닫았습니다." : "트렁크 닫기 명령을 전송했습니다.")
    }
}

struct StartClimateIntent: AppIntent {
    static var title: LocalizedStringResource = "에어컨 켜기"
    static var description = IntentDescription("BYD 차량 에어컨을 켭니다.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (service, vin, pin) = try await makeServiceContext()
        let s    = StorageManager.shared
        let temp = Double(s.acTargetTemp)
        let wind = s.acWindLevel > 0 ? s.acWindLevel : nil
        let ok   = try await service.startClimate(vin: vin, temp: temp,
                                                   durationMinutes: 20,
                                                   cycleMode: s.acCycleMode,
                                                   windLevel: wind, pin: pin)
        LogManager.shared.log("API", "Siri 에어컨 켜기: \(temp)°C → \(ok ? "성공" : "전송됨")")
        return .result(dialog: ok ? "에어컨을 켰습니다." : "에어컨 켜기 명령을 전송했습니다.")
    }
}

struct StopClimateIntent: AppIntent {
    static var title: LocalizedStringResource = "에어컨 끄기"
    static var description = IntentDescription("BYD 차량 에어컨을 끕니다.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (service, vin, pin) = try await makeServiceContext()
        let ok = try await service.stopClimate(vin: vin, pin: pin)
        LogManager.shared.log("API", "Siri 에어컨 끄기: \(ok ? "성공" : "전송됨")")
        return .result(dialog: ok ? "에어컨을 껐습니다." : "에어컨 끄기 명령을 전송했습니다.")
    }
}

// MARK: - Siri 단축어 자동 등록 (iOS 16.4+)

@available(iOS 16.4, *)
struct BydShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTrunkIntent(),
            phrases: ["\(.applicationName) 트렁크 열어", "\(.applicationName) 트렁크 열기"],
            shortTitle: "트렁크 열기",
            systemImageName: "car.rear.and.tire.marks"
        )
        AppShortcut(
            intent: CloseTrunkIntent(),
            phrases: ["\(.applicationName) 트렁크 닫아", "\(.applicationName) 트렁크 닫기"],
            shortTitle: "트렁크 닫기",
            systemImageName: "car.rear.road.lane.dashed"
        )
        AppShortcut(
            intent: LockCarIntent(),
            phrases: ["\(.applicationName) 차 잠가", "\(.applicationName) 차량 잠금"],
            shortTitle: "차량 잠금",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: UnlockCarIntent(),
            phrases: ["\(.applicationName) 차 열어", "\(.applicationName) 차량 잠금 해제"],
            shortTitle: "차량 잠금 해제",
            systemImageName: "lock.open.fill"
        )
        AppShortcut(
            intent: StartClimateIntent(),
            phrases: ["\(.applicationName) 에어컨 켜", "\(.applicationName) 에어컨 켜기"],
            shortTitle: "에어컨 켜기",
            systemImageName: "snowflake"
        )
        AppShortcut(
            intent: StopClimateIntent(),
            phrases: ["\(.applicationName) 에어컨 꺼", "\(.applicationName) 에어컨 끄기"],
            shortTitle: "에어컨 끄기",
            systemImageName: "snowflake.slash"
        )
    }
}
