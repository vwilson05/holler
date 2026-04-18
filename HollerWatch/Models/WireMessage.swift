import Foundation

// MARK: - Voice Message

struct VoiceMessage: Identifiable, Codable {
    let id: String
    let senderId: String
    let senderName: String
    let timestamp: Date
    let duration: TimeInterval
    let audioData: Data

    init(senderId: String, senderName: String, duration: TimeInterval, audioData: Data) {
        self.id = UUID().uuidString
        self.senderId = senderId
        self.senderName = senderName
        self.timestamp = Date()
        self.duration = duration
        self.audioData = audioData
    }
}

// MARK: - Wire Protocol (matches iOS app)

enum WireMessage: Codable {
    case voice(VoiceMessage)
    case presence(PresenceUpdate)
    case ping

    struct PresenceUpdate: Codable {
        let memberId: String
        let memberName: String
        let isOnline: Bool
    }
}

// MARK: - Member

struct Member: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var isOnline: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Member, rhs: Member) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Watch Settings Keys (synced from iPhone via WatchConnectivity)

enum WatchSettingsKey {
    static let displayName = "displayName"
    static let roomCode = "roomCode"
    static let relayURL = "relayURL"
    static let deviceId = "deviceId"
}
