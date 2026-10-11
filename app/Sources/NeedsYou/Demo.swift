import Foundation

/// Generic fixture data for --demo and the README screenshots.
enum Demo {
    @MainActor static func fill(_ s: NeedsStore) {
        let now = Date()
        s.permissions = [
            PermissionCard(id: "demo-1", sessionId: "d1", name: "api-server", tool: "Bash",
                           summary: "npm run test -- --watch=false", full: "npm run test -- --watch=false",
                           created: now.addingTimeInterval(-3 * 60), canOpen: true),
            PermissionCard(id: "demo-2", sessionId: "d2", name: "mobile-app", tool: "Edit",
                           summary: "~/code/mobile-app/src/screens/Settings.tsx",
                           full: "~/code/mobile-app/src/screens/Settings.tsx",
                           created: now.addingTimeInterval(-7 * 60), canOpen: true),
        ]
        s.waiting = [WaitingCard(id: "d3", name: "docs-site", since: now.addingTimeInterval(-11 * 60), canOpen: true,
                                 preview: "I updated the getting-started guide and fixed the two broken links. The search page still loads slowly on mobile. Do you want me to look into that next, or leave it for now?")]
        s.running = [
            RunningRow(id: "d4", name: "infra", folder: "code/infra", since: now.addingTimeInterval(-6 * 60)),
            RunningRow(id: "d5", name: "api-server", folder: "code/api-server", since: now.addingTimeInterval(-1 * 60)),
        ]
        s.idle = [
            RunningRow(id: "d6", name: "billing-service", folder: "code/billing-service", since: now.addingTimeInterval(-2 * 3600),
                       snippet: "All 48 tests pass. The refund endpoint now retries twice before failing."),
            RunningRow(id: "d7", name: "design-tokens", folder: "code/design-tokens", since: now.addingTimeInterval(-5 * 3600)),
        ]
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        s.done = [("docs-site", 15.9), ("infra", 14.6), ("mobile-app", 13.1)].enumerated().map { i, e in
            DoneRow(id: "x\(i)", time: today.addingTimeInterval(e.1 * 3600), name: e.0)
        }
        s.openCount = 7
    }

    @MainActor static func fill(_ s: UsageStore) {
        let week = s.range == .week
        let k = week ? 4.2 : 1.0
        func tok(_ m: Double) -> Int { Int(m * k * 1_000_000) }
        s.limits = LimitsInfo(rows: [
            LimitRow(id: "five_hour", label: "Current session", percent: 42, resets: Date().addingTimeInterval(2 * 3600 + 14 * 60 + 30)),
            LimitRow(id: "seven_day", label: "Weekly, all models", percent: 63, resets: Date().addingTimeInterval(3 * 86400)),
            LimitRow(id: "seven_day_opus", label: "Weekly, Opus", percent: 28, resets: Date().addingTimeInterval(3 * 86400)),
        ], capturedAt: Date().addingTimeInterval(-60), plan: "Max plan")
        func session(_ id: String, _ name: String, _ share: Double, _ m: Double, parts: [PartUsage] = [], heavy: [(label: String, share: Double)] = []) -> SessionUsage {
            SessionUsage(id: id, name: name, cost: share * 100, share: share, tokens: tok(m), parts: parts, heavy: heavy,
                         subAgentCount: max(0, parts.count - 1))
        }
        let first = session("u1", "api-server", 0.38, 9.1, parts: [
            PartUsage(id: "main", title: "Main conversation", model: "Opus 5.5", share: 0.71, subtitle: "74 replies, longest context 118k tokens", cost: 71),
            PartUsage(id: "a1", title: "Sub-agent: Research auth libraries", model: "Haiku 5.5", share: 0.09, subtitle: "general-purpose, 8 tool calls", cost: 9),
            PartUsage(id: "a2", title: "Sub-agent: Write integration tests", model: "Sonnet 5.5", share: 0.20, subtitle: "general-purpose, 41 tool calls", cost: 20),
        ], heavy: [("Screenshots", 0.34), ("Shell output", 0.22), ("File reads", 0.15)])
        s.sessions = [
            first,
            session("u2", "docs-site", 0.27, 6.4),
            session("u3", "mobile-app", 0.16, 3.8),
            session("u4", "infra", 0.11, 2.6),
            session("u5", "billing-service", 0.03, 0.8),
            session("u6", "design-tokens", 0.02, 0.5),
            session("u7", "scratch", 0.01, 0.3),
            session("u8", "release-notes", 0.01, 0.2),
            session("u9", "playground", 0.01, 0.1),
        ]
        s.loaded = true
        if s.expanded.isEmpty { s.expanded = ["u1"] }
    }
}
