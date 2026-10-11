import SwiftUI

/// Claude Code look. Resolved from the SwiftUI color scheme so live popovers and
/// offscreen screenshot rendering use the same path.
struct Palette {
    let bg, card, ink, soft, muted, line, accent, codeBg, button, buttonInk, track: Color

    private static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255, opacity: a)
    }

    static let light = Palette(
        bg: hex(0xFAF9F5), card: hex(0xFFFFFF), ink: hex(0x141413), soft: hex(0x3D3D3A), muted: hex(0x73726C),
        line: Color(.sRGB, red: 31 / 255, green: 30 / 255, blue: 29 / 255, opacity: 0.13), accent: hex(0xC6613F),
        codeBg: hex(0xF5F4ED), button: hex(0x141413), buttonInk: hex(0xFAF9F5), track: hex(0xEDEBE4))

    static let dark = Palette(
        bg: hex(0x262624), card: hex(0x30302E), ink: hex(0xFAF9F5), soft: hex(0xC2C0B6), muted: hex(0x9C9A92),
        line: Color(.sRGB, red: 222 / 255, green: 220 / 255, blue: 209 / 255, opacity: 0.15), accent: hex(0xD97757),
        codeBg: hex(0x1F1E1D), button: hex(0xFAF9F5), buttonInk: hex(0x141413), track: hex(0x1F1E1D))
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.light }
extension EnvironmentValues {
    var palette: Palette { get { self[PaletteKey.self] } set { self[PaletteKey.self] = newValue } }
}

/// Injects the palette for the current color scheme and paints the panel background.
struct ThemedRoot<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        let p = scheme == .dark ? Palette.dark : Palette.light
        content()
            .environment(\.palette, p)
            .foregroundStyle(p.ink)
            .background(p.bg)
    }
}

enum Fonts {
    static let body = Font.system(size: 13)
    static let small = Font.system(size: 12)
    static let title = Font.system(size: 19, design: .serif)
    static let mono = Font.system(size: 12, design: .monospaced)
}
