import SwiftUI

/// Reply box on a finished session's card, shown after clicking Reply. It takes focus at once;
/// Return sends, Option-Return adds a line, Escape closes it.
struct ReplyField: View {
    let onSend: (String) -> Void
    let onClose: () -> Void
    @Environment(\.palette) private var p
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if Screenshots.active {
                Text("Reply").foregroundStyle(p.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).strokeBorder(p.accent, lineWidth: 1))
            } else {
                TextField("Reply", text: $text, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...6)
                    .focused($focused)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? p.accent : p.line, lineWidth: 1))
                    .onSubmit(send)
                    .onExitCommand(perform: onClose)
                    .onAppear { DispatchQueue.main.async { focused = true } }
            }
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold)).foregroundStyle(p.buttonInk)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(p.button))
            }
            .buttonStyle(.plain)
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !Screenshots.active ? 0.4 : 1)
            .accessibilityLabel("Send reply")
        }
    }

    private func send() {
        let t = text
        guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        text = ""
        onSend(t)
    }
}

/// Small square icon button for card headers.
struct IconButton: View {
    let systemName: String
    let label: String
    var active = false
    let action: () -> Void
    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? p.accent : p.soft)
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(hover || active ? p.codeBg : .clear))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(p.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(label)
    }
}
