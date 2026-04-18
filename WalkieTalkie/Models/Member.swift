import Foundation
import UIKit

struct Member: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var isOnline: Bool
    var lastActiveAt: Date
    var isMuted: Bool
    var hapticPattern: HapticPattern

    init(
        id: String,
        name: String,
        isOnline: Bool = true,
        lastActiveAt: Date = Date(),
        isMuted: Bool = false,
        hapticPattern: HapticPattern = .pattern1
    ) {
        self.id = id
        self.name = name
        self.isOnline = isOnline
        self.lastActiveAt = lastActiveAt
        self.isMuted = isMuted
        self.hapticPattern = hapticPattern
    }

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var lastActiveFormatted: String {
        let interval = Date().timeIntervalSince(lastActiveAt)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

enum HapticPattern: String, Codable, CaseIterable, Identifiable {
    case pattern1, pattern2, pattern3, pattern4, pattern5, pattern6

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pattern1: return "Tap-Tap"
        case .pattern2: return "Buzz"
        case .pattern3: return "Heartbeat"
        case .pattern4: return "Triple Tap"
        case .pattern5: return "Crescendo"
        case .pattern6: return "Staccato"
        }
    }

    /// Each pattern is a sequence of (style, delay in seconds)
    var sequence: [(UIImpactFeedbackGenerator.FeedbackStyle, TimeInterval)] {
        switch self {
        case .pattern1:
            return [(.medium, 0.0), (.medium, 0.15)]
        case .pattern2:
            return [(.heavy, 0.0), (.light, 0.05), (.light, 0.10)]
        case .pattern3:
            return [(.heavy, 0.0), (.light, 0.12), (.heavy, 0.35), (.light, 0.47)]
        case .pattern4:
            return [(.light, 0.0), (.light, 0.10), (.light, 0.20)]
        case .pattern5:
            return [(.light, 0.0), (.medium, 0.12), (.heavy, 0.24)]
        case .pattern6:
            return [(.medium, 0.0), (.medium, 0.08), (.medium, 0.16), (.medium, 0.24)]
        }
    }
}
