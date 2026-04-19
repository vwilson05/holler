import SwiftUI

extension Color {
    // MARK: - Adaptive Holler Theme Colors

    static let hollerAccent = Color(hex: "#00C9A7")

    static let hollerBackground = Color(.hollerBackground)
    static let hollerCard = Color(.hollerCard)
    static let hollerCardElevated = Color(.hollerCardElevated)
    static let hollerTextPrimary = Color(.hollerTextPrimary)
    static let hollerTextSecondary = Color(.hollerTextSecondary)

    static let hollerRecording = Color(hex: "#FF3B30")
    static let hollerSent = Color(hex: "#34C759")
    static let hollerReceived = Color(hex: "#5AC8FA")
    static let hollerOnline = Color(hex: "#34C759")
    static let hollerOffline = Color(hex: "#636366")

    // MARK: - Hex Initializer

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 201, 167, 255) // fallback to accent
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - UIColor adaptive colors (light/dark)

extension UIColor {
    static let hollerBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 1)    // #0F0F0F
            : UIColor(red: 0.97, green: 0.96, blue: 0.95, alpha: 1)    // #F8F5F0
    }

    static let hollerCard = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)    // #1A1A1A
            : UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)      // #FFFFFF
    }

    static let hollerCardElevated = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.14, green: 0.14, blue: 0.14, alpha: 1)    // #242424
            : UIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1)    // #F5F5F5
    }

    static let hollerTextPrimary = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .white
            : UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)    // #1F1F1F
    }

    static let hollerTextSecondary = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.63, green: 0.63, blue: 0.63, alpha: 1)    // #A0A0A0
            : UIColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1)    // #737373
    }
}

extension View {
    func hollerCard() -> some View {
        self
            .background(Color.hollerCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}
