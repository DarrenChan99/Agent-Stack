import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

enum Theme {
    static let crimson = Color(hex: 0xE0354F), crimsonBright = Color(hex: 0xFF6B80), crimsonSoft = Color(hex: 0xFF8597)
    static let text = Color.white, textDim = Color.white, textFaint = Color.white
    static let green = Color(hex: 0x6EE7B0), amber = Color(hex: 0xF5C66B)
}

extension View {
    /// Dark glass panel: Liquid Glass on macOS 26, else material, plus a faint aurora tint.
    func perchPanel(radius: CGFloat = 18) -> some View {
        let aurora = LinearGradient(colors: [Theme.crimson.opacity(0.10), .clear, Color(hex: 0x6EA8FF).opacity(0.06)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
        return self
            .background(aurora, in: RoundedRectangle(cornerRadius: radius))
            .glass(radius)
            .preferredColorScheme(.dark)
    }

    @ViewBuilder fileprivate func glass(_ radius: CGFloat) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
        }
        #else
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
        #endif
    }
}

/// Glass + 1px crimson outline + soft glow. Never a solid red.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.crimsonBright, lineWidth: 1))
            .shadow(color: Theme.crimson.opacity(configuration.isPressed ? 0.7 : 0.4), radius: 6)
    }
}
