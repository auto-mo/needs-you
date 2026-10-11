import SwiftUI

struct UsagePanelView: View {
    @ObservedObject var store: UsageStore
    var scrollable = true
    var onQuit: () -> Void = {}
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 0) {
            FitOrScroll(scrollable: scrollable, maxHeight: 560) { content }
            PanelFooter(text: "Right-click for usage, click for Needs you", onQuit: onQuit)
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "Usage", trailing: store.limits?.plan)
            limits
            sessionsSection
            Text("Shares are estimated from each session's own records, weighted by model list price.")
                .font(Fonts.small).foregroundStyle(p.muted)
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
        }
        .font(Fonts.body)
    }

    // MARK: Plan limits

    @ViewBuilder private var limits: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let info = store.limits, !info.rows.isEmpty {
                ForEach(Array(info.rows.enumerated()), id: \.element.id) { i, row in
                    limitRow(row, accent: i == 0)
                }
                if let at = info.capturedAt {
                    Text("Limits as of \(Fmt.duration(Date().timeIntervalSince(at))) ago").font(Fonts.small).foregroundStyle(p.muted)
                }
            } else {
                Text("Plan limits appear after the status line script runs. See README.")
                    .font(Fonts.small).foregroundStyle(p.muted)
            }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 14)
    }

    private func limitRow(_ r: LimitRow, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(r.label)
                Spacer()
                Text([Fmt.percent(r.percent / 100), LimitsReader.resetText(r.resets)].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .font(Fonts.small).foregroundStyle(p.muted).monospacedDigit()
            }
            bar(fraction: r.percent / 100, color: accent ? p.accent : p.soft, height: 6, outlined: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func bar(fraction: Double, color: Color, height: CGFloat, outlined: Bool = false) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(p.track)
                    .overlay(Capsule().strokeBorder(outlined ? p.line : .clear, lineWidth: 1))
                Capsule().fill(color).frame(width: max(height, g.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
    }

    // MARK: Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("By session").font(.system(size: 12, weight: .medium)).foregroundStyle(p.muted)
                Spacer()
                segmented
            }
            .padding(.horizontal, 4).padding(.bottom, 6)

            if store.sessions.isEmpty {
                Text(store.loading || !store.loaded ? "Reading session records\u{2026}" : "No usage recorded in this period.")
                    .foregroundStyle(p.muted).padding(.horizontal, 4).padding(.vertical, 6)
            } else {
                let top = Array(store.sessions.prefix(6))
                let rest = Array(store.sessions.dropFirst(6))
                ForEach(Array(top.enumerated()), id: \.element.id) { i, s in
                    if i > 0 { Rectangle().fill(p.line).frame(height: 1) }
                    sessionRow(s)
                }
                if !rest.isEmpty { restBlock(rest) }
            }
        }
        .padding(.horizontal, 12)
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(UsageRange.allCases, id: \.self) { r in
                Button { store.setRange(r) } label: {
                    Text(r.rawValue).font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(store.range == r ? p.ink : p.muted)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(store.range == r ? p.card : .clear)
                            .shadow(color: .black.opacity(store.range == r ? 0.08 : 0), radius: 1, y: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show usage for \(r.rawValue.lowercased())")
                .accessibilityAddTraits(store.range == r ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(p.track))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.line, lineWidth: 1))
    }

    private func sessionRow(_ s: SessionUsage) -> some View {
        let open = store.expanded.contains(s.id)
        return VStack(alignment: .leading, spacing: 8) {
            Button { store.toggle(s.id) } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(p.muted)
                        .frame(width: 12, height: 20)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .animation(.easeOut(duration: 0.12), value: open)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(s.name).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                        bar(fraction: s.share, color: p.accent, height: 4)
                    }
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.percent(s.share)).foregroundStyle(p.ink)
                        Text("\(Fmt.tokens(s.tokens)) tokens").font(Fonts.small).foregroundStyle(p.muted)
                    }
                    .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(s.name), \(Fmt.percent(s.share)) of usage")
            .accessibilityHint(open ? "Collapse details" : "Show where it went")
            if open { detail(s).padding(.leading, 22) }
        }
        .padding(.vertical, 10).padding(.horizontal, 4)
    }

    private func detail(_ s: SessionUsage) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Where it went").font(.system(size: 12, weight: .medium)).foregroundStyle(p.muted)
                ForEach(s.parts) { part in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(part.title).lineLimit(2)
                            modelTag(part.model)
                            Spacer(minLength: 4)
                            Text(Fmt.percent(part.share)).monospacedDigit()
                        }
                        Text(part.subtitle).font(Fonts.small).foregroundStyle(p.muted)
                    }
                }
                if !s.heavy.isEmpty {
                    Text("Heaviest inputs").font(.system(size: 12, weight: .medium)).foregroundStyle(p.muted).padding(.top, 2)
                    ForEach(s.heavy, id: \.label) { h in
                        HStack { Text(h.label); Spacer(); Text(Fmt.percent(h.share)).monospacedDigit() }
                    }
                }
            }
        }
    }

    private func modelTag(_ m: String) -> some View {
        Text(m).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.muted)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(p.line, lineWidth: 1))
            .fixedSize()
    }

    private func restBlock(_ rest: [SessionUsage]) -> some View {
        let share = rest.reduce(0) { $0 + $1.share }
        let tokens = rest.reduce(0) { $0 + $1.tokens }
        return VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(p.line).frame(height: 1)
            Button { store.showRest.toggle() } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(p.muted)
                        .frame(width: 12, height: 20)
                        .rotationEffect(.degrees(store.showRest ? 90 : 0))
                        .animation(.easeOut(duration: 0.12), value: store.showRest)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(rest.count) more sessions").font(.system(size: 13.5, weight: .medium))
                        bar(fraction: share, color: p.accent, height: 4)
                    }
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.percent(share))
                        Text("\(Fmt.tokens(tokens)) tokens").font(Fonts.small).foregroundStyle(p.muted)
                    }
                    .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(rest.count) more sessions, \(Fmt.percent(share)) of usage")
            if store.showRest {
                VStack(spacing: 6) {
                    ForEach(rest) { s in
                        HStack {
                            Text(s.name).foregroundStyle(p.soft).lineLimit(1)
                            Spacer()
                            Text("\(Fmt.percent(s.share)) \u{00B7} \(Fmt.tokens(s.tokens)) tokens")
                                .font(Fonts.small).foregroundStyle(p.muted).monospacedDigit()
                        }
                    }
                }
                .padding(.leading, 22)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 4)
    }
}
