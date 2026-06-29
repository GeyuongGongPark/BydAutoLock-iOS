import Foundation
import UserNotifications

/// 로컬 알림 관리
/// - APNs 없이 UNUserNotificationCenter로 즉시 발송
final class NotificationManager {

    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let storage = StorageManager.shared
    private var lastSignalLostTime: Date?
    private static let signalLostCooldown: TimeInterval = 60

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
        send(
            id: "signal_lost",
            title: "차량 신호 끊김",
            body: "BLE 신호를 잃었습니다. 60초 후 자동으로 잠금됩니다.",
            sound: .default
        )
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
            sound: UNNotificationSound(named: UNNotificationSoundName("default"))
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

    // MARK: - Private

    private func send(id: String, title: String, body: String, sound: UNNotificationSound?) {
        // 동일 id의 기존 알림 제거 (알림 누적 방지)
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = sound

        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(req)
    }
}
