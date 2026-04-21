import Foundation

enum WireMessageType: String, Codable {
    case voice, location, join, leave, ping, pong, members, transcription, reaction
}

struct WireMessage: Codable {
    let type: WireMessageType
    let id: String
    let sender: String
    let senderID: String
    let room: String
    let timestamp: Int64
    let payload: WirePayload

    enum CodingKeys: String, CodingKey {
        case type, id, sender, room, timestamp, payload
        case senderID = "sender_id"
    }

    init(
        type: WireMessageType,
        id: String = UUID().uuidString,
        sender: String,
        senderID: String,
        room: String,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        payload: WirePayload
    ) {
        self.type = type
        self.id = id
        self.sender = sender
        self.senderID = senderID
        self.room = room
        self.timestamp = timestamp
        self.payload = payload
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    func encodedString() throws -> String {
        let data = try encoded()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func decode(from data: Data) throws -> WireMessage {
        try JSONDecoder().decode(WireMessage.self, from: data)
    }

    static func decode(from string: String) throws -> WireMessage {
        guard let data = string.data(using: .utf8) else {
            throw WireError.invalidData
        }
        return try decode(from: data)
    }
}

enum WirePayload: Codable {
    case voice(VoicePayload)
    case location(LocationPayload)
    case members(MembersPayload)
    case transcription(TranscriptionPayload)
    case reaction(ReactionPayload)
    case empty

    struct VoicePayload: Codable {
        let audio: String // base64 AAC
        let durationMs: Int

        enum CodingKeys: String, CodingKey {
            case audio
            case durationMs = "duration_ms"
        }
    }

    struct LocationPayload: Codable {
        let lat: Double
        let lng: Double
        let accuracy: Double
    }

    struct MembersPayload: Codable {
        let members: [MemberInfo]

        struct MemberInfo: Codable {
            let id: String
            let name: String
            let online: Bool
        }
    }

    struct TranscriptionPayload: Codable {
        let messageID: String
        let text: String

        enum CodingKeys: String, CodingKey {
            case messageID = "message_id"
            case text
        }
    }

    struct ReactionPayload: Codable {
        let messageID: String
        let emoji: String

        enum CodingKeys: String, CodingKey {
            case messageID = "message_id"
            case emoji
        }
    }

    enum CodingKeys: String, CodingKey {
        case audio, durationMs = "duration_ms"
        case lat, lng, accuracy
        case members
        case messageID = "message_id", text
        case emoji
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let audio = try? container.decode(String.self, forKey: .audio) {
            let durationMs = (try? container.decode(Int.self, forKey: .durationMs)) ?? 0
            self = .voice(VoicePayload(audio: audio, durationMs: durationMs))
        } else if let lat = try? container.decode(Double.self, forKey: .lat) {
            let lng = (try? container.decode(Double.self, forKey: .lng)) ?? 0
            let accuracy = (try? container.decode(Double.self, forKey: .accuracy)) ?? 0
            self = .location(LocationPayload(lat: lat, lng: lng, accuracy: accuracy))
        } else if let members = try? container.decode([MembersPayload.MemberInfo].self, forKey: .members) {
            self = .members(MembersPayload(members: members))
        } else if let messageID = try? container.decode(String.self, forKey: .messageID),
                  let emoji = try? container.decode(String.self, forKey: .emoji) {
            self = .reaction(ReactionPayload(messageID: messageID, emoji: emoji))
        } else if let messageID = try? container.decode(String.self, forKey: .messageID) {
            let text = (try? container.decode(String.self, forKey: .text)) ?? ""
            self = .transcription(TranscriptionPayload(messageID: messageID, text: text))
        } else {
            self = .empty
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .voice(let p):
            try container.encode(p.audio, forKey: .audio)
            try container.encode(p.durationMs, forKey: .durationMs)
        case .location(let p):
            try container.encode(p.lat, forKey: .lat)
            try container.encode(p.lng, forKey: .lng)
            try container.encode(p.accuracy, forKey: .accuracy)
        case .members(let p):
            try container.encode(p.members, forKey: .members)
        case .transcription(let p):
            try container.encode(p.messageID, forKey: .messageID)
            try container.encode(p.text, forKey: .text)
        case .reaction(let p):
            try container.encode(p.messageID, forKey: .messageID)
            try container.encode(p.emoji, forKey: .emoji)
        case .empty:
            break
        }
    }
}

enum WireError: Error {
    case invalidData
    case encodingFailed
}
