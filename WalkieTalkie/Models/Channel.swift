import Foundation
import CryptoKit

enum ConnectionMode: String, Codable, CaseIterable, Identifiable {
    case lan       // Multipeer only — voice stays on local network
    case relay     // WebSocket only — works across networks
    case auto      // Try both (Multipeer + relay)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lan: return "Same WiFi"
        case .relay: return "Anywhere"
        case .auto: return "Auto"
        }
    }

    var description: String {
        switch self {
        case .lan: return "Private. Voice never leaves your network."
        case .relay: return "Works across any network via relay server."
        case .auto: return "Uses local WiFi when available, relay as fallback."
        }
    }
}

enum ChannelMode: String, Codable, CaseIterable, Identifiable {
    case home, roadtrip, event, hangout, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .home: return "Home"
        case .roadtrip: return "Road Trip"
        case .event: return "Event"
        case .hangout: return "Hangout"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .roadtrip: return "car.fill"
        case .event: return "party.popper.fill"
        case .hangout: return "person.3.fill"
        case .custom: return "star.fill"
        }
    }

    var defaultColorHex: String {
        switch self {
        case .home: return "#00C9A7"
        case .roadtrip: return "#4ECDC4"
        case .event: return "#FFE66D"
        case .hangout: return "#A78BFA"
        case .custom: return "#60A5FA"
        }
    }
}

struct Channel: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var code: String
    var groupName: String
    var passphrase: String
    var mode: ChannelMode
    var colorHex: String
    var createdAt: Date
    var locationSharingEnabled: Bool
    var locationSharingExpiry: Date?
    var connectionMode: ConnectionMode

    init(
        id: UUID = UUID(),
        name: String,
        code: String = "",
        groupName: String = "",
        passphrase: String = "",
        mode: ChannelMode = .home,
        colorHex: String = "#00C9A7",
        createdAt: Date = Date(),
        locationSharingEnabled: Bool = false,
        locationSharingExpiry: Date? = nil,
        connectionMode: ConnectionMode = .auto
    ) {
        self.id = id
        self.name = name
        self.code = code
        self.groupName = groupName
        self.passphrase = passphrase
        self.mode = mode
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.locationSharingEnabled = locationSharingEnabled
        self.locationSharingExpiry = locationSharingExpiry
        self.connectionMode = connectionMode
    }

    // Custom Codable to default connectionMode for channels saved before this field existed
    enum CodingKeys: String, CodingKey {
        case id, name, code, groupName, passphrase, mode, colorHex, createdAt
        case locationSharingEnabled, locationSharingExpiry, connectionMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        code = try container.decode(String.self, forKey: .code)
        groupName = try container.decode(String.self, forKey: .groupName)
        passphrase = try container.decode(String.self, forKey: .passphrase)
        mode = try container.decode(ChannelMode.self, forKey: .mode)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        locationSharingEnabled = try container.decode(Bool.self, forKey: .locationSharingEnabled)
        locationSharingExpiry = try container.decodeIfPresent(Date.self, forKey: .locationSharingExpiry)
        connectionMode = try container.decodeIfPresent(ConnectionMode.self, forKey: .connectionMode) ?? .auto
    }

    /// Compute a deterministic room code from group name + passphrase using SHA-256
    static func roomCode(groupName: String, passphrase: String) -> String {
        let input = groupName.isEmpty ? passphrase : "\(groupName):\(passphrase)"
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func defaultHome() -> Channel {
        Channel(name: "Home", code: "default-home", groupName: "", passphrase: "", mode: .home, colorHex: ChannelMode.home.defaultColorHex)
    }

    var isLocationSharingActive: Bool {
        guard locationSharingEnabled else { return false }
        if let expiry = locationSharingExpiry {
            return Date() < expiry
        }
        return true
    }

    var bonjourServiceType: String {
        "_hlr\(code.prefix(8).lowercased())._tcp"
    }
}
