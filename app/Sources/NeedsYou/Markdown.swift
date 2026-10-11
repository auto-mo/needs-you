import SwiftUI

/// Small Markdown renderer for session replies: headings, bullets, code blocks and inline styles.
/// SwiftUI's own Markdown support is inline only, so block structure is handled line by line.
enum Markdown {
    static func render(_ source: String) -> AttributedString {
        var out = AttributedString()
        var inCode = false
        for (i, raw) in source.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inCode.toggle(); continue }
            if i > 0 && !out.characters.isEmpty { out += AttributedString("\n") }
            if inCode {
                var a = AttributedString(raw)
                a.font = .system(size: 12, design: .monospaced)
                out += a
                continue
            }
            if line.range(of: #"^\|?[\s:|-]+\|[\s:|-]*$"#, options: .regularExpression) != nil { continue } // table rule
            if let h = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                var a = inline(String(line[h.upperBound...]))
                a.font = .system(size: 13, weight: .semibold)
                out += a
            } else if let b = line.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                out += AttributedString("•  ") + inline(String(line[b.upperBound...]))
            } else {
                out += inline(raw)
            }
        }
        return out
    }

    /// First paragraph as plain text, for the collapsed view.
    static func summary(_ source: String) -> String {
        let paragraphs = source.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let first = paragraphs.first { !$0.isEmpty && !$0.hasPrefix("```") } ?? source
        return String(render(first).characters)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func inline(_ s: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }
}

/// A session's message: a short summary, and the full rendered message when you click the box.
struct MessageBox: View {
    let text: String
    var maxHeight: CGFloat = 260
    @Environment(\.palette) private var p
    @State private var expanded: Bool

    init(text: String, maxHeight: CGFloat = 260, startExpanded: Bool = false) {
        self.text = text
        self.maxHeight = maxHeight
        _expanded = State(initialValue: startExpanded)
    }

    private var expandable: Bool { text.count > 160 || text.contains("\n") }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if expanded {
                    ViewThatFits(in: .vertical) {
                        full
                        ScrollView(.vertical) { full }
                    }
                    .frame(maxHeight: maxHeight)
                } else {
                    Text(Markdown.summary(text)).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .padding(.trailing, expandable ? 14 : 0)
                }
            }
            .foregroundStyle(p.soft)
            if expandable {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(p.muted)
                    .padding(8)
                    .accessibilityHidden(true)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(p.codeBg))
        .contentShape(Rectangle())
        .onTapGesture { if expandable { expanded.toggle() } }
        .accessibilityAddTraits(expandable ? .isButton : [])
        .accessibilityHint(expandable ? (expanded ? "Collapse message" : "Expand full message") : "")
        .onDisappear { expanded = false }
    }

    private var full: some View {
        Text(Markdown.render(text))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8).padding(.bottom, 10)
    }
}
