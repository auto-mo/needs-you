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



/// Makes a whole row open its session on click, with a hover highlight.
struct OpenOnClick: ViewModifier {
    let action: () -> Void
    @Environment(\.palette) private var p
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8).fill(p.codeBg.opacity(hover ? 1 : 0)))
            .onHover { hover = $0 }
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
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
    var onRefresh: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 8) {
            MarkImage()
            Text(title).font(Fonts.title).accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing { Text(trailing).font(Fonts.small).foregroundStyle(p.muted).monospacedDigit() }
            if let onRefresh { RefreshButton(action: onRefresh) }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }
}


/// Reloads the panel; one quick turn of the arrow confirms the click, since the reload is instant.
struct RefreshButton: View {
    let action: () -> Void
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turns = 0.0
    @State private var hover = false

    var body: some View {
        Button {
            action()
            if !reduceMotion { withAnimation(.easeOut(duration: 0.45)) { turns += 1 } }
        } label: {
            Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hover ? p.ink : p.muted)
                .rotationEffect(.degrees(turns * 360))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(hover ? p.codeBg : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel("Refresh")
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
    /// Opens one Code session in the Claude desktop app with the app's own claude://code/continue
    /// link. The app only accepts its own session ids (local_...), not Claude Code's session ids.
    static func open(hostSessionId: String?) {
        guard let id = hostSessionId,
              let url = URL(string: "claude://code/continue?session=\(id)&source=needs_you") else { return openClaudeDesktop() }
        NSWorkspace.shared.open(url)
    }

    static func openClaudeDesktop() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: desktopBundleId) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
