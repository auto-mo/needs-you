import SwiftUI

struct NeedsPanelView: View {
    @ObservedObject var store: NeedsStore
    var scrollable = true
    var onQuit: () -> Void = {}
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 0) {
            FitOrScroll(scrollable: scrollable) { content }
            PanelFooter(text: "Answers go straight to the session", onQuit: onQuit)
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var yourTurnCount: Int { store.permissions.count + store.waiting.count }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "Needs you", trailing: "\(store.openCount) sessions open")

            section("Your turn", count: yourTurnCount) {
                if yourTurnCount == 0 {
                    muted("Nothing needs you right now.")
                } else {
                    ForEach(store.permissions) { permissionCard($0) }
                    ForEach(store.waiting) { waitingCard($0) }
                }
            }
            section("Running now", count: store.running.count) {
                if store.running.isEmpty {
                    muted("Nothing running.")
                } else {
                    ForEach(Array(store.running.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Rectangle().fill(p.line).frame(height: 1) }
                        openable(r.id, runningRow(r, busy: true))
                    }
                }
            }
            if !store.idle.isEmpty {
                section("Idle", count: store.idle.count) {
                    ForEach(Array(store.idle.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Rectangle().fill(p.line).frame(height: 1) }
                        openable(r.id, runningRow(r, busy: false))
                    }
                }
            }
            section("Done today", count: store.done.count) {
                if store.done.isEmpty {
                    muted("Nothing finished yet today.")
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(store.done) { d in
                            openable(d.id, HStack(spacing: 8) {
                                Text(Fmt.clockTime(d.time)).font(Fonts.small).foregroundStyle(p.muted).monospacedDigit()
                                    .frame(minWidth: 44, alignment: .leading)
                                Text("\(d.name) finished").foregroundStyle(p.soft).lineLimit(1)
                                Spacer(minLength: 0)
                            }.padding(.vertical, 2))
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .font(Fonts.body)
    }

    private func section<C: View>(_ title: String, count: Int, @ViewBuilder _ body: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: title, count: count)
            body()
        }
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 10)
    }

    private func muted(_ s: String) -> some View {
        Text(s).foregroundStyle(p.muted).padding(.horizontal, 4)
    }

    private func nameRow(_ name: String, _ since: Date) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(p.accent).frame(width: 7, height: 7)
                Text(name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("waiting \(Fmt.duration(Date().timeIntervalSince(since)))")
                .font(Fonts.small).foregroundStyle(p.muted).monospacedDigit().lineLimit(1)
        }
    }

    private func permissionCard(_ c: PermissionCard) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                nameRow(c.name, c.created)
                (Text("Wants to use ") + Text(c.tool).font(Fonts.mono)).foregroundStyle(p.soft)
                Text(c.summary)
                    .font(Fonts.mono).lineLimit(4).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(p.codeBg))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.line, lineWidth: 1))
                    .help(c.full)
                HStack(spacing: 6) {
                    Button("Allow") { store.answer(c, .allow) }
                        .buttonStyle(PillButtonStyle(kind: .solid))
                        .accessibilityLabel("Allow \(c.tool) for \(c.name)")
                    Button("Deny") { store.answer(c, .deny) }
                        .buttonStyle(PillButtonStyle(kind: .outline))
                        .accessibilityLabel("Deny \(c.tool) for \(c.name)")
                    Spacer()
                    if c.canOpen { openLink(c.name, c.sessionId) }
                }
            }
        }
        .padding(.bottom, 0)
    }

    private func waitingCard(_ w: WaitingCard) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                nameRow(w.name, w.since)
                Text("Finished. Its last message:").foregroundStyle(p.muted).font(Fonts.small)
                if let t = w.preview { ReplyPreview(text: t) } else {
                    Text("Finished and is waiting for your next message").foregroundStyle(p.soft)
                }
                if w.canOpen { openLink(w.name, w.id, prominent: true) }
            }
        }
    }

    @ViewBuilder
    private func openLink(_ name: String, _ sessionId: String, prominent: Bool = false) -> some View {
        Button(prominent ? "Reply in session" : "Open session") { Opener.open(sessionId: sessionId) }
            .buttonStyle(PillButtonStyle(kind: prominent ? .solid : .link))
            .accessibilityLabel("Open session \(name)")
    }

    /// Wraps a row so clicking anywhere on it opens the session (desktop sessions only).
    @ViewBuilder
    private func openable<V: View>(_ id: String, _ row: V) -> some View {
        if store.desktop.contains(id) || store.demo {
            Button { Opener.open(sessionId: id) } label: { row }
                .buttonStyle(RowButtonStyle())
                .help("Open this session in Claude")
        } else {
            row
        }
    }

    private func runningRow(_ r: RunningRow, busy: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(r.folder).font(Fonts.small).foregroundStyle(p.muted).lineLimit(1).truncationMode(.middle)
                if let s = r.snippet {
                    Text(s).font(Fonts.small).foregroundStyle(p.soft).lineLimit(2).padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if busy { Image(systemName: "asterisk").foregroundStyle(p.accent).font(.system(size: 11, weight: .bold)) }
                if let s = r.since {
                    Text((busy ? "" : "idle ") + Fmt.duration(Date().timeIntervalSince(s))).foregroundStyle(p.muted)
                }
            }
            .font(Fonts.small).monospacedDigit()
        }
        .padding(.vertical, 7).padding(.horizontal, 4)
    }
}
