import SwiftUI
import UserNotifications

@main
struct HollerApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var connection = ConnectionManager.shared
    @StateObject private var audio = AudioManager.shared

    init() {
        // Request notification permissions on launch (fallback for background audio)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[App] Notification permission error: \(error)")
            }
            print("[App] Notification permission granted: \(granted)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if settings.isSetUp {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(settings)
            .environmentObject(connection)
            .environmentObject(audio)
            .preferredColorScheme(settings.appTheme.colorScheme)
        }
    }
}
