import SwiftUI

// MARK: - App Settings (persisted singleton)

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults(suiteName: "group.com.holler.shared") ?? .standard

    @Published var displayName: String {
        didSet { defaults.set(displayName, forKey: "displayName") }
    }

    @Published var deviceID: String {
        didSet { defaults.set(deviceID, forKey: "deviceID") }
    }

    @Published var groupName: String {
        didSet { defaults.set(groupName, forKey: "groupName") }
    }

    @Published var relayServerURL: String {
        didSet { defaults.set(relayServerURL, forKey: "relayServerURL") }
    }

    @Published var channels: [Channel] {
        didSet { persistChannels() }
    }

    @Published var activeChannelID: UUID? {
        didSet {
            if let id = activeChannelID {
                defaults.set(id.uuidString, forKey: "activeChannelID")
            }
            // Defer Watch sync to avoid circular init (AppSettings.init → syncToWatch → AppSettings.shared)
            DispatchQueue.main.async {
                WatchSyncManager.shared.syncToWatch()
            }
        }
    }

    @Published var notificationSound: Bool {
        didSet { defaults.set(notificationSound, forKey: "notificationSound") }
    }

    @Published var notificationHaptic: Bool {
        didSet { defaults.set(notificationHaptic, forKey: "notificationHaptic") }
    }

    @Published var notificationBanner: Bool {
        didSet { defaults.set(notificationBanner, forKey: "notificationBanner") }
    }

    @Published var audioQuality: AudioQuality {
        didSet { defaults.set(audioQuality.rawValue, forKey: "audioQuality") }
    }

    @Published var stayActiveInBackground: Bool {
        didSet { defaults.set(stayActiveInBackground, forKey: "stayActiveInBackground") }
    }

    /// When true, the app uses Apple's PushToTalk framework to show a
    /// floating pill in the Dynamic Island + Lock Screen and to enable
    /// system-level "talk from anywhere" (Bluetooth accessory buttons too).
    /// When false, the app is a normal foreground-first app: no Island,
    /// no Lock Screen pill. Incoming-message background playback is
    /// completely separate (see `stayActiveInBackground`) and unaffected.
    /// Opt-in per beta feedback (default OFF, 2026-04-23).
    @Published var systemPTTEnabled: Bool {
        didSet { defaults.set(systemPTTEnabled, forKey: "systemPTTEnabled") }
    }

    enum AppTheme: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    @Published var appTheme: AppTheme {
        didSet { defaults.set(appTheme.rawValue, forKey: "appTheme") }
    }

    var isSetUp: Bool {
        !displayName.isEmpty
    }

    var activeChannel: Channel? {
        get { channels.first(where: { $0.id == activeChannelID }) }
        set {
            if let channel = newValue, let idx = channels.firstIndex(where: { $0.id == channel.id }) {
                channels[idx] = channel
                activeChannelID = channel.id
            }
        }
    }

    private init() {
        let storedName = defaults.string(forKey: "displayName") ?? ""
        let storedDevice = defaults.string(forKey: "deviceID") ?? UUID().uuidString
        let storedRelay = defaults.string(forKey: "relayServerURL") ?? "wss://holler-relay-production.up.railway.app"

        let storedGroup = defaults.string(forKey: "groupName") ?? ""

        self.displayName = storedName
        self.deviceID = storedDevice
        self.groupName = storedGroup
        // Default to Railway relay if not set (or was empty from prior version)
        self.relayServerURL = storedRelay.isEmpty ? "wss://holler-relay-production.up.railway.app" : storedRelay
        self.notificationSound = defaults.object(forKey: "notificationSound") as? Bool ?? true
        self.notificationHaptic = defaults.object(forKey: "notificationHaptic") as? Bool ?? true
        self.notificationBanner = defaults.object(forKey: "notificationBanner") as? Bool ?? true
        self.audioQuality = AudioQuality(rawValue: defaults.string(forKey: "audioQuality") ?? "") ?? .medium
        self.appTheme = AppTheme(rawValue: defaults.string(forKey: "appTheme") ?? "") ?? .dark
        self.stayActiveInBackground = defaults.object(forKey: "stayActiveInBackground") as? Bool ?? true
        // Default OFF — beta feedback 2026-04-23: system PTT (Dynamic Island /
        // Lock Screen) should be explicit opt-in, not on by default.
        self.systemPTTEnabled = defaults.object(forKey: "systemPTTEnabled") as? Bool ?? false

        // Load channels
        if let data = defaults.data(forKey: "channels"),
           let decoded = try? JSONDecoder().decode([Channel].self, from: data) {
            self.channels = decoded
        } else {
            self.channels = [Channel.defaultHome()]
        }

        if let idString = defaults.string(forKey: "activeChannelID"),
           let id = UUID(uuidString: idString) {
            self.activeChannelID = id
        } else {
            self.activeChannelID = channels.first?.id
        }

        // Persist deviceID on first launch
        if defaults.string(forKey: "deviceID") == nil {
            defaults.set(storedDevice, forKey: "deviceID")
        }

        // One-time migration: update old orange accent to teal
        if !defaults.bool(forKey: "migratedColorV2") {
            for i in channels.indices {
                if channels[i].colorHex == "#FF6B47" {
                    channels[i].colorHex = "#00C9A7"
                }
            }
            persistChannels()
            defaults.set(true, forKey: "migratedColorV2")
        }
    }

    private func persistChannels() {
        if let data = try? JSONEncoder().encode(channels) {
            defaults.set(data, forKey: "channels")
        }
    }

    func addChannel(_ channel: Channel) {
        channels.append(channel)
        activeChannelID = channel.id
    }

    func removeChannel(_ channel: Channel) {
        channels.removeAll(where: { $0.id == channel.id })
        if activeChannelID == channel.id {
            activeChannelID = channels.first?.id
        }
    }
}

// MARK: - Audio Quality

enum AudioQuality: String, Codable, CaseIterable, Identifiable {
    case low, medium, high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: return "Low (16kbps)"
        case .medium: return "Medium (32kbps)"
        case .high: return "High (64kbps)"
        }
    }

    var bitRate: Int {
        switch self {
        case .low: return 16000
        case .medium: return 32000
        case .high: return 64000
        }
    }

    var sampleRate: Double {
        switch self {
        case .low: return 16000
        case .medium: return 22050
        case .high: return 44100
        }
    }
}
