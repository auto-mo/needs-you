import Foundation

struct LiveSession {
    let pid: Int32
    let sessionId: String
    let cwd: String
    let name: String?
    let status: String
    let entrypoint: String?
    /// The desktop app's id for this session (local_...), which its claude://code links require.
    let hostSessionId: String?
    let updatedAt: Date
    let statusUpdatedAt: Date?
}

/// Read-only view of ~/.claude/sessions and ~/.claude/projects. Both are undocumented, so best effort.
enum SessionDirectory {
    static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// Sessions whose process is still running.
    static func loadLive() -> [LiveSession] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Paths.sessions, includingPropertiesForKeys: nil)) ?? []
        var out: [LiveSession] = []
        for u in urls where u.pathExtension == "json" {
            guard let j = readJSON(u), let sid = j["sessionId"] as? String,
                  let pid = (j["pid"] as? NSNumber)?.int32Value, isAlive(pid) else { continue }
            out.append(LiveSession(
                pid: pid, sessionId: sid, cwd: j["cwd"] as? String ?? "", name: j["name"] as? String,
                status: j["status"] as? String ?? "", entrypoint: j["entrypoint"] as? String,
                hostSessionId: j["hostSessionId"] as? String,
                updatedAt: Date(timeIntervalSince1970: epochSeconds(j["updatedAt"]) ?? 0),
                statusUpdatedAt: epochSeconds(j["statusUpdatedAt"]).map { Date(timeIntervalSince1970: $0) }))
        }
        return out
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var projectDirCache: [String: URL] = [:]

    /// ~/.claude/projects/<dir> that holds this session.
    static func projectDir(sessionId: String, transcriptPath: String?) -> URL? {
        if let t = transcriptPath, !t.isEmpty { return URL(fileURLWithPath: t).deletingLastPathComponent() }
        lock.lock(); defer { lock.unlock() }
        if let c = projectDirCache[sessionId] { return c }
        let fm = FileManager.default
        for d in (try? fm.contentsOfDirectory(at: Paths.projects, includingPropertiesForKeys: nil)) ?? [] {
            if fm.fileExists(atPath: d.appendingPathComponent(sessionId + ".jsonl").path)
                || fm.fileExists(atPath: d.appendingPathComponent(sessionId).path) {
                projectDirCache[sessionId] = d
                return d
            }
        }
        return nil
    }

    static func customTitle(sessionId: String, projectDir: URL?) -> String? {
        guard let dir = projectDir else { return nil }
        guard let j = readJSON(dir.appendingPathComponent(sessionId).appendingPathComponent("custom-title.json")) else { return nil }
        for k in ["customTitle", "title"] {
            if let s = j[k] as? String, !s.isEmpty { return s }
        }
        return nil
    }

    static func lastComponent(_ cwd: String) -> String {
        let c = URL(fileURLWithPath: cwd).lastPathComponent
        return c.isEmpty || c == "/" ? "Session" : c
    }

    /// Last two path components, for the folder line.
    static func folder(_ cwd: String) -> String {
        let parts = cwd.split(separator: "/")
        return parts.suffix(2).joined(separator: "/")
    }

    /// sessions/<pid>.json `name`, else custom-title.json, else the folder name.
    static func resolveName(sessionId: String, cwd: String?, sessionName: String?, projectDir: URL?) -> String {
        if let n = sessionName, !n.isEmpty { return n }
        if let t = customTitle(sessionId: sessionId, projectDir: projectDir ?? self.projectDir(sessionId: sessionId, transcriptPath: nil)) { return t }
        return lastComponent(cwd ?? "")
    }
}
