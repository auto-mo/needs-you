import SwiftUI

/// Reply box on a finished session's card. Return sends; Option-Return adds a line.
struct ReplyField: View {
    /// Returns false when the reply was copied for pasting instead of sent.
    let onSend: (String) -> Bool
    @Environment(\.palette) private var p
    @State private var text = ""
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            field
            if copied {
                Text("Copied. Paste it in the session.").font(Fonts.small).foregroundStyle(p.muted)
            }
        }
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if Screenshots.active {
                Text("Reply").foregroundStyle(p.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).strokeBorder(p.line, lineWidth: 1))
            } else {
                TextField("Reply", text: $text, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...6)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).strokeBorder(p.line, lineWidth: 1))
                    .onSubmit(send)
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
        copied = !onSend(t)
    }
}
