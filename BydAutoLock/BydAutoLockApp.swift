import SwiftUI

@main
struct BydAutoLockApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("app_color_scheme") private var colorSchemeRaw: String = "system"

    var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(resolvedScheme)
        }
    }

    private var resolvedScheme: ColorScheme? {
        switch colorSchemeRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
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
