import SwiftUI

struct NeedsPanelView: View {
    @ObservedObject var store: NeedsStore
    var scrollable = true
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 0) {
            FitOrScroll(scrollable: scrollable) { content }
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

    /// Name, waiting time and, for desktop sessions, a small Open button on the right.
    private func header(_ name: String, _ since: Date, open sessionId: String?, reply replyId: String? = nil) -> some View {
        HStack(spacing: 8) {
            Circle().fill(p.accent).frame(width: 7, height: 7)
            Text(name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 6)
            Text(Fmt.duration(Date().timeIntervalSince(since)))
                .font(Fonts.small).foregroundStyle(p.muted).monospacedDigit().lineLimit(1)
            if let rid = replyId {
                IconButton(systemName: "arrowshape.turn.up.left", label: "Reply to \(name)",
                           active: store.replyOpen == rid) {
                    store.replyOpen = store.replyOpen == rid ? nil : rid
                }
            }
            if let sid = sessionId, store.openIds[sid] != nil || store.demo {
                IconButton(systemName: "arrow.up.right.square", label: "Open session \(name)") {
                    Opener.open(hostSessionId: store.openIds[sid])
                }
            }
        }
    }

    @ViewBuilder
    private func permissionCard(_ c: PermissionCard) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                header(c.name, c.created, open: c.canOpen ? c.sessionId : nil)
                if let qs = c.questions {
                    QuestionForm(questions: qs) { store.answer(c, answers: $0) }
                } else if let plan = c.plan {
                    Text("Wants to start on this plan").foregroundStyle(p.soft)
                    MessageBox(text: plan)
                    decisionButtons(c, allow: "Approve", deny: "Keep planning")
                } else {
                    (Text("Wants to use ") + Text(c.tool).font(Fonts.mono)).foregroundStyle(p.soft)
                    Text(c.summary)
                        .font(Fonts.mono).lineLimit(4).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(p.codeBg))
                        .help(c.full)
                    decisionButtons(c, allow: "Allow", deny: "Deny")
                }
            }
        }
    }

    private func decisionButtons(_ c: PermissionCard, allow: String, deny: String) -> some View {
        HStack(spacing: 6) {
            Button(allow) { store.answer(c, .allow) }
                .buttonStyle(PillButtonStyle(kind: .solid))
                .accessibilityLabel("\(allow) \(c.tool) for \(c.name)")
            Button(deny) { store.answer(c, .deny) }
                .buttonStyle(PillButtonStyle(kind: .outline))
                .accessibilityLabel("\(deny) \(c.tool) for \(c.name)")
        }
    }

    private func waitingCard(_ w: WaitingCard) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                header(w.name, w.since, open: w.canOpen ? w.id : nil,
                       reply: store.replyable.contains(w.id) || store.demo ? w.id : nil)
                if let t = w.preview { MessageBox(text: t) } else {
                    Text("Finished and is waiting for your next message").foregroundStyle(p.soft)
                }
                if store.replyOpen == w.id {
                    ReplyField(onSend: { store.reply(to: w.id, text: $0) }, onClose: { store.replyOpen = nil })
                }
            }
        }
    }

    /// Clicking anywhere on the row opens the session (desktop sessions only).
    @ViewBuilder
    private func openable<V: View>(_ id: String, _ row: V) -> some View {
        if store.openIds[id] != nil || store.demo {
            row.modifier(OpenOnClick { Opener.open(hostSessionId: store.openIds[id]) })
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
