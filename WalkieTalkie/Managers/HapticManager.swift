import UIKit

/// Plays haptic identity patterns for incoming voice messages
final class HapticManager {
    static let shared = HapticManager()

    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)

    private init() {
        // Prepare generators for lower latency
        lightGenerator.prepare()
        mediumGenerator.prepare()
        heavyGenerator.prepare()
    }

    func playPattern(_ pattern: HapticPattern) {
        let sequence = pattern.sequence

        for (style, delay) in sequence {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.impactForStyle(style)
            }
        }
    }

    func playRecordStart() {
        heavyGenerator.impactOccurred(intensity: 1.0)
    }

    func playSent() {
        mediumGenerator.impactOccurred(intensity: 0.7)
    }

    func playReceived() {
        lightGenerator.impactOccurred(intensity: 0.5)
    }

    private func impactForStyle(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        switch style {
        case .light:
            lightGenerator.impactOccurred()
        case .medium:
            mediumGenerator.impactOccurred()
        case .heavy:
            heavyGenerator.impactOccurred()
        default:
            mediumGenerator.impactOccurred()
        }
    }

    /// Preview a haptic pattern (for settings screen)
    func previewPattern(_ pattern: HapticPattern) {
        // Prepare all generators
        lightGenerator.prepare()
        mediumGenerator.prepare()
        heavyGenerator.prepare()

        playPattern(pattern)
    }
}
