import WatchConnectivity
import Foundation

/// iPhone 측 WatchConnectivity 관리
/// Watch → iPhone 명령 수신, iPhone → Watch 상태 전송
@MainActor
final class WatchConnectivityManager: NSObject {

    static let shared = WatchConnectivityManager()

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Watch로 최신 상태 전송 (applicationContext - 마지막 값 유지)
    func sendStatusToWatch(isRunning: Bool, isLocked: Bool?, battery: Int?, rssi: Int?) {
        guard WCSession.default.activationState == .activated else { return }
        var ctx: [String: Any] = ["isRunning": isRunning]
        if let v = isLocked { ctx["isLocked"] = v }
        if let v = battery  { ctx["battery"]  = v }
        if let v = rssi     { ctx["rssi"]     = v }
        try? WCSession.default.updateApplicationContext(ctx)
    }
}

extension WatchConnectivityManager: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    /// Watch에서 명령 수신 (lock / unlock / start / stop)
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = message["command"] as? String else { return }
        Task { @MainActor in
            switch command {
            case "lock":   AutoLockService.shared.manualLock()
            case "unlock": AutoLockService.shared.manualUnlock()
            case "start":  AutoLockService.shared.start()
            case "stop":   AutoLockService.shared.stop()
            default: break
            }
        }
    }
}
