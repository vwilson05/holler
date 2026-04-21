import SwiftUI
import UserNotifications

@main
struct HollerApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var connection = ConnectionManager.shared
    @StateObject private var audio = AudioManager.shared
    @StateObject private var systemPTT = PTTSystemManager.shared

    init() {
        // Request notification permissions on launch (fallback for background audio)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[App] Notification permission error: \(error)")
            }
            print("[App] Notification permission granted: \(granted)")
        }

        // Initialize system PTT (Apple PushToTalk framework)
        PTTSystemManager.shared.setup()
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
            .environmentObject(systemPTT)
            .preferredColorScheme(settings.appTheme.colorScheme)
            .onOpenURL { url in
                handleIncomingURL(url)
            }
        }
    }

    /// Handle incoming URLs from Universal Links (holleratme.app/join?g=...&p=...)
    /// or custom URL scheme (holler://join?g=...&p=...)
    private func handleIncomingURL(_ url: URL) {
        print("[App] Incoming URL: \(url)")

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            print("[App] Failed to parse URL components")
            return
        }

        let queryItems = components.queryItems ?? []
        guard let groupName = queryItems.first(where: { $0.name == "g" })?.value,
              let passphrase = queryItems.first(where: { $0.name == "p" })?.value else {
            print("[App] Missing g or p query params")
            return
        }

        let trimmedGroup = groupName.trimmingCharacters(in: .whitespaces)
        let trimmedPass = passphrase.trimmingCharacters(in: .whitespaces)
        let code = Channel.roomCode(groupName: trimmedGroup, passphrase: trimmedPass)

        // Check if we already have this channel
        if let existing = settings.channels.first(where: { $0.code == code }) {
            print("[App] Channel already exists, switching to it")
            connection.switchChannel(to: existing)
            return
        }

        // Create and join the channel
        let channelName = trimmedGroup.isEmpty ? "Shared Channel" : trimmedGroup
        let channel = Channel(
            name: channelName,
            code: code,
            groupName: trimmedGroup,
            passphrase: trimmedPass,
            mode: .custom,
            connectionMode: .auto
        )
        settings.addChannel(channel)
        connection.switchChannel(to: channel)
        print("[App] Joined channel from URL: \(channelName) (\(code.prefix(6)))")
    }
}
