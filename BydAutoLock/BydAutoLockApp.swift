import SwiftUI

@main
struct BydAutoLockApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        NotificationManager.shared.requestAuthorization()
        let storage = StorageManager.shared
        // 앱 시작 시 서비스 자동 시작
        if storage.isServiceEnabled && storage.hasCredentials && storage.deviceMac != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AutoLockService.shared.start()
            }
        }
        return true
    }

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
