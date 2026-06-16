import WatchConnectivity
import Foundation
import WidgetKit

/// Watch 측 WatchConnectivity 관리
/// iPhone → Watch 상태 수신, Watch → iPhone 명령 전송
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {

    static let shared = WatchConnectivityManager()

    @Published var isRunning   = false
    @Published var isLocked:   Bool? = nil
    @Published var battery:    Int?  = nil
    @Published var rssi:       Int?  = nil
    @Published var isReachable = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// iPhone으로 명령 전송
    func sendCommand(_ command: String) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["command": command], replyHandler: nil, errorHandler: nil)
    }

    private func applyContext(_ ctx: [String: Any]) {
        if let v = ctx["isRunning"] as? Bool { isRunning = v }
        if let v = ctx["isLocked"]  as? Bool { isLocked  = v }
        if let v = ctx["battery"]   as? Int  { battery   = v }
        if let v = ctx["rssi"]      as? Int  { rssi      = v }
        persistForComplication()
    }

    /// 컴플리케이션 Provider가 읽을 수 있도록 UserDefaults에 저장
    private func persistForComplication() {
        let d = UserDefaults.standard
        d.set(isRunning, forKey: "watch_isRunning")
        if let v = isLocked { d.set(v, forKey: "watch_isLocked") }
        if let v = battery  { d.set(v, forKey: "watch_battery") }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension WatchConnectivityManager: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.applyContext(session.receivedApplicationContext)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isReachable = session.isReachable }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.applyContext(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.applyContext(message) }
    }
}
