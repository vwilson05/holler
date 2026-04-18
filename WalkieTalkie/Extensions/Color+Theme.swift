import SwiftUI

extension Color {
    // MARK: - Holler Theme Colors

    static let hollerAccent = Color(hex: "#00C9A7")
    static let hollerBackground = Color(hex: "#0F0F0F")
    static let hollerCard = Color(hex: "#1A1A1A")
    static let hollerCardElevated = Color(hex: "#242424")
    static let hollerTextPrimary = Color.white
    static let hollerTextSecondary = Color(hex: "#A0A0A0")
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

extension View {
    func hollerCard() -> some View {
        self
            .background(Color.hollerCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}
