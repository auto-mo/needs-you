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

/// A whole row that opens its session; highlights on hover so it reads as clickable.
struct RowButtonStyle: ButtonStyle {
    @Environment(\.palette) private var p
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8).fill(p.codeBg.opacity(hover || configuration.isPressed ? 1 : 0)))
            .onHover { hover = $0 }
    }
}

/// The last reply of a session, a few lines at first, with Show more.
struct ReplyPreview: View {
    let text: String
    @Environment(\.palette) private var p
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if expanded {
                    ScrollView(.vertical) { body(text).fixedSize(horizontal: false, vertical: true) }
                        .frame(height: 200)
                } else {
                    body(text).lineLimit(4)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(p.codeBg))
            if text.count > 220 || text.filter({ $0 == "\n" }).count > 3 {
                Button(expanded ? "Show less" : "Show more") { expanded.toggle() }
                    .buttonStyle(PillButtonStyle(kind: .link))
            }
        }
        .onDisappear { expanded = false }
    }

    private func body(_ s: String) -> some View {
        Text(s).foregroundStyle(p.soft).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
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
