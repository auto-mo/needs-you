import SwiftUI

/// Options for a session's question (the AskUserQuestion tool). One single-choice question is
/// answered with one click; several questions or multi-select need Submit.
struct QuestionForm: View {
    let questions: [[String: Any]]
    let onSubmit: ([String: String]) -> Void
    @Environment(\.palette) private var p
    @State private var picked: [String: Set<String>] = [:]
    @State private var other: [String: String] = [:]

    private var oneClick: Bool { questions.count == 1 && !(questions[0]["multiSelect"] as? Bool ?? false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(questions.enumerated()), id: \.offset) { _, q in
                question(q)
            }
            if !oneClick {
                Button("Submit") { onSubmit(answers()) }
                    .buttonStyle(PillButtonStyle(kind: .solid))
                    .disabled(answers().count < questions.count)
                    .opacity(answers().count < questions.count ? 0.5 : 1)
            }
        }
    }

    private func question(_ q: [String: Any]) -> some View {
        let text = q["question"] as? String ?? ""
        let multi = q["multiSelect"] as? Bool ?? false
        let options = q["options"] as? [[String: Any]] ?? []
        return VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                let label = o["label"] as? String ?? ""
                let on = picked[text]?.contains(label) ?? false
                Button {
                    if oneClick { onSubmit([text: label]); return }
                    var s = picked[text] ?? []
                    if multi { if on { s.remove(label) } else { s.insert(label) } } else { s = [label] }
                    picked[text] = s
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(p.ink)
                        if let d = o["description"] as? String, !d.isEmpty {
                            Text(d).font(Fonts.small).foregroundStyle(p.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(on ? p.accent.opacity(0.12) : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? p.accent : p.line, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            if !Screenshots.active { otherField(text) }
        }
    }

    private func otherField(_ text: String) -> some View {
            TextField("Other answer", text: Binding(get: { other[text] ?? "" }, set: { other[text] = $0 }))
                .textFieldStyle(.roundedBorder).font(Fonts.small)
                .onSubmit {
                    guard let o = other[text], !o.isEmpty else { return }
                    if oneClick { onSubmit([text: o]) } else { picked[text] = [o] }
                }
    }

    private func answers() -> [String: String] {
        var out: [String: String] = [:]
        for q in questions {
            let text = q["question"] as? String ?? ""
            if let s = picked[text], !s.isEmpty { out[text] = s.sorted().joined(separator: ", ") }
        }
        return out
    }
}
