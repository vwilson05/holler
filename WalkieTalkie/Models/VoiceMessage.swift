import Foundation

struct MessageReaction: Codable, Equatable, Identifiable {
    var id: String { "\(senderID)-\(emoji)" }
    let senderID: String
    let senderName: String
    let emoji: String
}

struct VoiceMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let senderID: String
    let senderName: String
    let channelID: UUID
    let timestamp: Date
    let durationMs: Int
    let audioData: Data
    var transcription: String?
    var isPlayed: Bool
    var reactions: [MessageReaction]

    init(
        id: UUID = UUID(),
        senderID: String,
        senderName: String,
        channelID: UUID,
        timestamp: Date = Date(),
        durationMs: Int,
        audioData: Data,
        transcription: String? = nil,
        isPlayed: Bool = false,
        reactions: [MessageReaction] = []
    ) {
        self.id = id
        self.senderID = senderID
        self.senderName = senderName
        self.channelID = channelID
        self.timestamp = timestamp
        self.durationMs = durationMs
        self.audioData = audioData
        self.transcription = transcription
        self.isPlayed = isPlayed
        self.reactions = reactions
    }

    var durationFormatted: String {
        let seconds = durationMs / 1000
        let ms = (durationMs % 1000) / 100
        if seconds < 60 {
            return "\(seconds).\(ms)s"
        }
        let minutes = seconds / 60
        let secs = seconds % 60
        return "\(minutes):\(String(format: "%02d", secs))"
    }

    var isFromCurrentUser: Bool {
        senderID == AppSettings.shared.deviceID
    }
}
