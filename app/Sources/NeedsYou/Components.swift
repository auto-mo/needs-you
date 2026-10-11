import SwiftUI
import AppKit

struct PillButtonStyle: ButtonStyle {
    enum Kind { case solid, outline, link }
    let kind: Kind
    @Environment(\.palette) private var p

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label.font(.system(size: 12.5, weight: .medium))
        Group {
            switch kind {
            case .solid:
                label.foregroundStyle(p.buttonInk).padding(.horizontal, 12).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(p.button))
            case .outline:
                label.foregroundStyle(p.ink).padding(.horizontal, 12).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).strokeBorder(p.line, lineWidth: 1))
            case .link:
                label.foregroundStyle(p.muted).underline().padding(.vertical, 5)
            }
        }
        .opacity(configuration.isPressed ? 0.7 : 1)
        .contentShape(Rectangle())
    }
}

struct Card<Content: View>: View {
    @Environment(\.palette) private var p
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(p.card))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(p.line, lineWidth: 1))
    }
}

struct SectionHeader: View {
    @Environment(\.palette) private var p
    let title: String
    var count: Int?
    var body: some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(p.muted)
            if let count { Text("\(count)").foregroundStyle(p.soft).monospacedDigit() }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

struct MarkImage: View {
    @Environment(\.palette) private var p
    var body: some View {
        Image(nsImage: StatusIcon.current).interpolation(.none).renderingMode(.template)
            .resizable().scaledToFit().frame(height: 16).foregroundStyle(p.accent)
            .accessibilityHidden(true)
    }
}

struct PanelHeader: View {
    @Environment(\.palette) private var p
    let title: String
    let trailing: String?
    var body: some View {
        HStack(spacing: 8) {
            MarkImage()
            Text(title).font(Fonts.title).accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing { Text(trailing).font(Fonts.small).foregroundStyle(p.muted).monospacedDigit() }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }
}

struct PanelFooter: View {
    @Environment(\.palette) private var p
    let text: String
    let onQuit: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(p.line).frame(height: 1)
            HStack {
                Text(text).foregroundStyle(p.muted)
                Spacer()
                Button("Quit", action: onQuit).buttonStyle(PillButtonStyle(kind: .link)).accessibilityLabel("Quit Needs You")
            }
            .font(Fonts.small)
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
        }
    }
}

/// Scrolls only when the content would exceed `maxHeight`.
struct FitOrScroll<Content: View>: View {
    let scrollable: Bool
    var maxHeight: CGFloat = 575
    @ViewBuilder var content: () -> Content
    var body: some View {
        if scrollable {
            ViewThatFits(in: .vertical) {
                content()
                ScrollView(.vertical, showsIndicators: false) { content() }
            }
            .frame(maxHeight: maxHeight)
        } else {
            content()
        }
    }
}

enum Opener {
    static let desktopBundleId = "com.anthropic.claudefordesktop"
    // TODO: deep link to the exact session
    static func openClaudeDesktop() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: desktopBundleId) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
