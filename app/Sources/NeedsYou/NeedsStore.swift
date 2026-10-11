import Foundation
import SwiftUI

struct PermissionCard: Identifiable {
    let id: String
    let sessionId: String
    let name: String
    let tool: String
    let summary: String
    let full: String
    let created: Date
    let canOpen: Bool
}

struct WaitingCard: Identifiable {
    let id: String
    let name: String
    let since: Date
    let canOpen: Bool
}

struct RunningRow: Identifiable {
    let id: String
    let name: String
    let folder: String
    let since: Date?
}

struct DoneRow: Identifiable {
    let id: String
    let time: Date
    let name: String
}

enum Decision: String { case allow, deny }

@MainActor
final class NeedsStore: ObservableObject {
    @Published var permissions: [PermissionCard] = []
    @Published var waiting: [WaitingCard] = []
    @Published var running: [RunningRow] = []
    @Published var idle: [RunningRow] = []
    @Published var done: [DoneRow] = []
    @Published var openCount = 0

    let demo: Bool
    private var hidden = Set<String>()

    init(demo: Bool = false) {
        self.demo = demo
        if demo { Demo.fill(self) }
    }

    // MARK: Protocol folder

    static func ensureDirs() {
        let fm = FileManager.default
        for sub in ["", "pending", "answers"] {
            try? fm.createDirectory(at: Paths.needsDir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
    }

    static func writeHeartbeat() {
        let url = Paths.needsDir.appendingPathComponent("app.heartbeat")
        try? Data("\(Int(Date().timeIntervalSince1970))\n".utf8).write(to: url, options: .atomic)
    }

    /// Atomic write of answers/<id>.json per PROTOCOL.md.
    static func writeAnswer(id: String, decision: Decision, message: String? = nil) {
        var obj: [String: Any] = ["version": 1, "id": id, "decision": decision.rawValue,
                                  "answered_at": Date().timeIntervalSince1970]
        if let m = message { obj["message"] = m }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        let dir = Paths.needsDir.appendingPathComponent("answers")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent(id + ".json"), options: .atomic)
    }

    func answer(_ card: PermissionCard, _ decision: Decision) {
        if !demo { Self.writeAnswer(id: card.id, decision: decision) }
        hidden.insert(card.id)
        permissions.removeAll { $0.id == card.id }
    }

    // MARK: Refresh

    func refresh() {
        guard !demo else { return }
        let now = Date()
        let live = SessionDirectory.loadLive()
        let bySession = Dictionary(live.map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })
        let events = readEvents()

        func name(_ sid: String, cwd: String?, transcript: String?) -> String {
            SessionDirectory.resolveName(sessionId: sid, cwd: cwd ?? bySession[sid]?.cwd, sessionName: bySession[sid]?.name,
                                         projectDir: SessionDirectory.projectDir(sessionId: sid, transcriptPath: transcript))
        }
        func desktop(_ sid: String) -> Bool { bySession[sid]?.entrypoint == "claude-desktop" }

        // Pending permission prompts. A dead hook pid means the prompt was answered elsewhere.
        var perms: [PermissionCard] = []
        let pendingDir = Paths.needsDir.appendingPathComponent("pending")
        var present = Set<String>()
        for u in (try? FileManager.default.contentsOfDirectory(at: pendingDir, includingPropertiesForKeys: nil)) ?? [] where u.pathExtension == "json" {
            guard let j = readJSON(u) else { continue }
            let id = j["id"] as? String ?? u.deletingPathExtension().lastPathComponent
            if let pid = (j["hook_pid"] as? NSNumber)?.int32Value, !SessionDirectory.isAlive(pid) {
                try? FileManager.default.removeItem(at: u)
                continue
            }
            present.insert(id)
            if hidden.contains(id) { continue }
            let sid = j["session_id"] as? String ?? ""
            let tool = j["tool_name"] as? String ?? "a tool"
            let input = j["tool_input"] as? [String: Any] ?? [:]
            let (summary, full) = Self.summarize(tool: tool, input: input)
            perms.append(PermissionCard(
                id: id, sessionId: sid, name: name(sid, cwd: j["cwd"] as? String, transcript: j["transcript_path"] as? String),
                tool: tool, summary: summary, full: full,
                created: Date(timeIntervalSince1970: epochSeconds(j["created_at"]) ?? now.timeIntervalSince1970),
                canOpen: desktop(sid)))
        }
        hidden.formIntersection(present)
        perms.sort { $0.created < $1.created }

        // Sessions that finished and wait for a reply: stop/idle after the latest prompt.
        var waitingSince: [String: Event] = [:]
        var lastStopToday: [String: Event] = [:]
        let midnight = Calendar.current.startOfDay(for: now)
        for e in events {
            switch e.kind {
            case "prompt", "end": waitingSince[e.sessionId] = nil
            case "stop", "idle": if waitingSince[e.sessionId] == nil { waitingSince[e.sessionId] = e }
            default: break
            }
            if e.kind == "stop", e.ts >= midnight { lastStopToday[e.sessionId] = e }
        }
        let permSessions = Set(perms.map(\.sessionId))
        var waits: [WaitingCard] = []
        for (sid, e) in waitingSince {
            guard let s = bySession[sid], s.status == "idle", now.timeIntervalSince(e.ts) < 12 * 3600,
                  !permSessions.contains(sid) else { continue }
            waits.append(WaitingCard(id: sid, name: name(sid, cwd: e.cwd, transcript: e.transcript), since: e.ts, canOpen: desktop(sid)))
        }
        waits.sort { $0.since < $1.since }

        let runs = live.filter { $0.status == "busy" }.map {
            RunningRow(id: $0.sessionId, name: name($0.sessionId, cwd: $0.cwd, transcript: nil),
                       folder: SessionDirectory.folder($0.cwd), since: $0.statusUpdatedAt ?? $0.updatedAt)
        }.sorted { ($0.since ?? now) < ($1.since ?? now) }

        // Every other open session, most recently active first, so nothing open is invisible.
        let shown = permSessions.union(waits.map(\.id))
        let idles = live.filter { $0.status != "busy" && !shown.contains($0.sessionId) }.map {
            RunningRow(id: $0.sessionId, name: name($0.sessionId, cwd: $0.cwd, transcript: nil),
                       folder: SessionDirectory.folder($0.cwd), since: $0.statusUpdatedAt ?? $0.updatedAt)
        }.sorted { ($0.since ?? .distantPast) > ($1.since ?? .distantPast) }

        let dones = lastStopToday.values.sorted { $0.ts > $1.ts }.prefix(8).map {
            DoneRow(id: $0.sessionId, time: $0.ts, name: name($0.sessionId, cwd: $0.cwd, transcript: $0.transcript))
        }

        permissions = perms
        waiting = waits
        running = runs
        idle = idles
        done = Array(dones)
        openCount = live.count
    }

    // MARK: Parsing

    struct Event { let kind: String; let ts: Date; let sessionId: String; let cwd: String?; let transcript: String? }

    private func readEvents() -> [Event] {
        guard let text = try? String(contentsOf: Paths.needsDir.appendingPathComponent("events.jsonl"), encoding: .utf8) else { return [] }
        var out: [Event] = []
        for line in text.split(separator: "\n") {
            guard let j = json(Data(line.utf8)), let kind = j["event"] as? String, let sid = j["session_id"] as? String,
                  let ts = epochSeconds(j["ts"]) else { continue }
            out.append(Event(kind: kind, ts: Date(timeIntervalSince1970: ts), sessionId: sid,
                             cwd: j["cwd"] as? String, transcript: j["transcript_path"] as? String))
        }
        return out.sorted { $0.ts < $1.ts }
    }

    /// (display text, full text) for the tool-input box.
    static func summarize(tool: String, input: [String: Any]) -> (String, String) {
        func compact() -> String {
            guard let d = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes]),
                  let s = String(data: d, encoding: .utf8) else { return "" }
            return s
        }
        let text: String
        switch tool {
        case "Bash": text = input["command"] as? String ?? compact()
        case "Edit", "Write", "Read", "MultiEdit", "NotebookEdit": text = input["file_path"] as? String ?? compact()
        case "WebFetch": text = input["url"] as? String ?? compact()
        default: text = compact()
        }
        return (text, text)
    }
}
