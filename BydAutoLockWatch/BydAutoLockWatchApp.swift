import SwiftUI

@main
struct BydAutoLockWatchApp: App {

    @StateObject private var conn = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchMainView()
            }
            // 딥링크 처리: 컴플리케이션 버튼 탭 시 잠금/해제 즉시 실행
            .onOpenURL { url in
                guard url.scheme == "bydautolock" else { return }
                switch url.host {
                case "unlock": conn.sendCommand("unlock")
                case "lock":   conn.sendCommand("lock")
                default: break
                }
            }
        }
    }
}
