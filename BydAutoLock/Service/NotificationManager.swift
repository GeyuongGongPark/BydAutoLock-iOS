import Foundation
import UserNotifications

/// 로컬 알림 관리
/// - APNs 없이 UNUserNotificationCenter로 즉시 발송
final class NotificationManager {

    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let storage = StorageManager.shared
    private var lastSignalLostTime: Date?
    private static let signalLostCooldown: TimeInterval = 300   // 5분 (BLE 20초 사이클 알림 폭탄 방지)

    private init() {}

    // MARK: - Permission

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                LogManager.shared.log("Notification", "알림 권한 허용됨")
            }
        }
    }

    func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    // MARK: - Send

    func sendLockUnlock(isUnlock: Bool, isManual: Bool) {
        guard storage.notifyLockUnlock else { return }
        let auto = isManual ? "수동" : "자동"
        send(
            id: "lock_unlock",
            title: isUnlock ? "잠금 해제됨" : "차량 잠금됨",
            body: isUnlock
                ? "차량 잠금이 해제됐습니다 (\(auto))"
                : "차량이 잠겼습니다 (\(auto))",
            sound: .default
        )
    }

    func sendSignalLost() {
        guard storage.notifySignalLost else { return }
        let now = Date()
        if let last = lastSignalLostTime, now.timeIntervalSince(last) < Self.signalLostCooldown { return }
        lastSignalLostTime = now
        // 30초 지연 발송 — BLE 재연결 사이클(~20초)이나 isDriving 전환 지연으로 인한
        // 오탐 알림 방지. 신호 복구 시 cancelSignalLostNotification()으로 취소됨.
        send(
            id: "signal_lost",
            title: "차량 신호 끊김",
            body: "BLE 신호를 잃었습니다. 60초 내 미복구 시 안전 잠금합니다.",
            sound: .default,
            delay: 30
        )
    }

    func cancelSignalLostNotification() {
        center.removePendingNotificationRequests(withIdentifiers: ["signal_lost"])
        // pending 알림이 취소됐으므로 쿨다운도 리셋 — 다음 소실 시 즉시 알림 가능하도록
        lastSignalLostTime = nil
    }

    func resetSignalLostCooldown() {
        lastSignalLostTime = nil
    }

    func sendAcStarted(temp: Double) {
        guard storage.notifyAc else { return }
        send(
            id: "ac_start",
            title: "에어컨 켜짐",
            body: String(format: "에어컨이 자동으로 시작됐습니다 (목표: %.1f°C)", temp),
            sound: .default
        )
    }

    func sendAcStopped() {
        guard storage.notifyAc else { return }
        send(
            id: "ac_stop",
            title: "에어컨 꺼짐",
            body: "에어컨이 자동으로 종료됐습니다.",
            sound: .default
        )
    }

    func sendServiceStarted() {
        guard storage.notifyService else { return }
        send(
            id: "service_start",
            title: "서비스 시작",
            body: "BYD AutoLock 자동 잠금 서비스가 시작됐습니다.",
            sound: .default
        )
    }

    func sendServiceStopped() {
        guard storage.notifyService else { return }
        send(
            id: "service_stop",
            title: "서비스 중지",
            body: "BYD AutoLock 자동 잠금 서비스가 중지됐습니다.",
            sound: .default
        )
    }

    func sendLowBattery(percent: Int) {
        guard storage.notifyLowBattery,
              percent <= storage.lowBatteryThreshold else { return }
        send(
            id: "low_battery",
            title: "차량 배터리 부족",
            body: "차량 배터리가 \(percent)% 남았습니다.",
            sound: .default
        )
    }

    func sendPinNotConfigured() {
        send(
            id: "pin_not_configured",
            title: "작동 비밀번호 미설정",
            body: "BYD 앱에서 작동 비밀번호(핀)를 설정해야 원격 제어가 동작합니다.",
            sound: .default
        )
    }

    func sendAutoActionSuppressed() {
        send(
            id: "auto_suppressed",
            title: "자동 잠금/해제 일시 중단",
            body: "신호가 불안정해 자동 동작이 5분간 차단됩니다. 수동 제어는 정상 동작합니다.",
            sound: .default
        )
    }

    func sendLockFailed(isUnlock: Bool) {
        send(
            id: "lock_failed",
            title: isUnlock ? "잠금 해제 실패" : "잠금 실패",
            body: isUnlock
                ? "잠금 해제 명령이 전달되지 않았습니다. 차량 상태를 확인해주세요."
                : "잠금 명령이 전달되지 않았습니다. 차량 상태를 확인해주세요.",
            sound: .default
        )
    }

    // MARK: - Private

    private func send(id: String, title: String, body: String, sound: UNNotificationSound?, delay: TimeInterval = 0) {
        // 동일 id의 기존 알림 제거 (알림 누적 방지)
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = sound

        let trigger: UNNotificationTrigger? = delay > 0
            ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            : nil
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(req)
    }
}
