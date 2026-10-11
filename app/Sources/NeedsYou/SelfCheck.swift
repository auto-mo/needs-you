import Foundation

/// Headless logic checks: `NeedsYou --check`. Not shipped behaviour, just verification.
@MainActor
enum SelfCheck {
    static func run() {
        checkProtocol()
        checkScanner()
    }

    private static func checkProtocol() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("needsyou-check-\(getpid())")
        try? FileManager.default.removeItem(at: tmp)
        setenv("NEEDS_YOU_DIR", tmp.path, 1)
        NeedsStore.ensureDirs()
        NeedsStore.writeHeartbeat()
        let pending = tmp.appendingPathComponent("pending")
        let id = "1791676000123-\(getpid())"
        let body: [String: Any] = ["version": 1, "id": id, "kind": "permission", "created_at": Date().timeIntervalSince1970 - 180,
                                   "hook_pid": Int(getpid()), "session_id": "sess-1", "cwd": "/tmp/demo-project",
                                   "tool_name": "Bash", "tool_input": ["command": "npm test"]]
        try? JSONSerialization.data(withJSONObject: body).write(to: pending.appendingPathComponent(id + ".json"))
        let stale: [String: Any] = ["id": "stale-1", "hook_pid": 99999999, "session_id": "s2", "tool_name": "Read", "tool_input": [:]]
        try? JSONSerialization.data(withJSONObject: stale).write(to: pending.appendingPathComponent("stale-1.json"))

        let store = NeedsStore()
        store.refresh()
        print("heartbeat exists:", FileManager.default.fileExists(atPath: tmp.appendingPathComponent("app.heartbeat").path))
        print("pending listed:", store.permissions.map { "\($0.id) \($0.tool) \"\($0.summary)\" name=\($0.name)" })
        print("stale file deleted:", !FileManager.default.fileExists(atPath: pending.appendingPathComponent("stale-1.json").path))
        if let card = store.permissions.first {
            store.answer(card, .allow)
            let a = tmp.appendingPathComponent("answers/\(id).json")
            print("answer file:", (try? String(contentsOf: a, encoding: .utf8)) ?? "MISSING")
            print("card hidden after answer:", store.permissions.isEmpty)
        }
        try? FileManager.default.removeItem(at: tmp)
    }

    private static func checkScanner() {
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            let t0 = Date()
            let snap = await UsageScanner.shared.snapshot(range: .today)
            let stats = await UsageScanner.shared.statsBySession
            print(String(format: "scan today: %.1fs, %d sessions", Date().timeIntervalSince(t0), snap.sessions.count))
            for s in snap.sessions.prefix(5) {
                let st = stats[s.id] ?? ScanStats()
                print(String(format: "  %@  %4.1f%%  %@ tokens  sub-agents=%d  raw assistant lines=%d unique replies=%d",
                             s.name.padding(toLength: 34, withPad: " ", startingAt: 0), s.share * 100, Fmt.tokens(s.tokens),
                             s.subAgentCount, st.rawAssistantLines, st.uniqueReplies))
                for p in s.parts.prefix(3) { print("      \(p.title) [\(p.model)] \(Fmt.percent(p.share)) - \(p.subtitle)") }
                print("      heaviest: " + s.heavy.map { "\($0.label) \(Fmt.percent($0.share))" }.joined(separator: ", "))
            }
            let t1 = Date()
            _ = await UsageScanner.shared.snapshot(range: .today)
            print(String(format: "rescan (cached): %.2fs", Date().timeIntervalSince(t1)))
            let w0 = Date()
            let wk = await UsageScanner.shared.snapshot(range: .week)
            print(String(format: "scan week: %.1fs, %d sessions", Date().timeIntervalSince(w0), wk.sessions.count))
            sem.signal()
        }
        sem.wait()
    }
}
