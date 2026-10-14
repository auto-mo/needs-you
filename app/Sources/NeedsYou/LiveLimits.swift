import Foundation

/// Live plan limits from Anthropic's usage service: the same request Claude Code's /usage makes,
/// with the sign-in Claude Code keeps in the Keychain. The token stays in memory for the request;
/// it is never written to disk, logged, or sent anywhere but api.anthropic.com.
///
/// The Keychain token lasts about 8 hours and only the claude command line renews it. When it has
/// expired, this runs one tiny Haiku request (`claude -p`) so Claude Code renews its own sign-in,
/// at most a few times a day. The hook ignores that request (NEEDS_YOU_SKIP).
actor LiveLimits {
    static let shared = LiveLimits()
    private var lastFetch = Date.distantPast
    private(set) var lastError: String?

    struct Credential { let token: String; let expires: Date; let plan: String? }

    /// Fetches unless the last fetch was under a minute ago; `force` skips that wait.
    func refresh(force: Bool) async {
        if !force && Date().timeIntervalSince(lastFetch) < 60 { return }
        lastFetch = Date()
        guard var cred = Self.readCredential() else { lastError = "Sign in to Claude Code to see plan limits"; return }
        if cred.expires < Date().addingTimeInterval(60) {
            Self.renewSignIn()
            guard let renewed = Self.readCredential(), renewed.expires > Date() else {
                lastError = "Couldn't renew the Claude Code sign-in"; return
            }
            cred = renewed
        }
        do {
            let rows = try await Self.fetch(cred)
            Self.save(rows: rows, plan: cred.plan)
            lastError = nil
        } catch {
            lastError = "Couldn't reach the usage service"
        }
    }

    // MARK: Keychain

    static func readCredential() -> Credential? {
        guard let out = run("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"], timeout: 10),
              let j = json(out), let o = j["claudeAiOauth"] as? [String: Any],
              let token = o["accessToken"] as? String, let ms = (o["expiresAt"] as? NSNumber)?.doubleValue else { return nil }
        let plan = (o["subscriptionType"] as? String).map { $0.capitalized + " plan" }
        return Credential(token: token, expires: Date(timeIntervalSince1970: ms / 1000), plan: plan)
    }

    // MARK: Sign-in renewal

    static func renewSignIn() {
        guard let claude = claudePath() else { return }
        let dir = Paths.needsDir.appendingPathComponent("needs-you-refresh")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var env = ProcessInfo.processInfo.environment
        env["NEEDS_YOU_SKIP"] = "1"
        _ = run(claude, ["-p", "--model", "haiku", "Reply with OK"], cwd: dir, env: env, timeout: 90)
    }

    static func claudePath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for p in ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        guard let out = run("/bin/zsh", ["-lc", "command -v claude"], timeout: 10) else { return nil }
        let p = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? nil : p
    }

    // MARK: Usage service

    static func fetch(_ cred: Credential) async throws -> [[String: Any]] {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
        req.setValue("Bearer \(cred.token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("needs-you", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let j = json(data) else { throw URLError(.badServerResponse) }
        return rows(from: j)
    }

    /// Rows from the response's `limits` list (session, weekly, weekly per model), with the
    /// five_hour / seven_day fields as a fallback if that list is missing.
    static func rows(from j: [String: Any]) -> [[String: Any]] {
        func epoch(_ v: Any?) -> Double? {
            guard let s = v as? String else { return epochSeconds(v) }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d.timeIntervalSince1970 }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: s)?.timeIntervalSince1970
        }
        if let limits = j["limits"] as? [[String: Any]], !limits.isEmpty {
            return limits.compactMap { l in
                guard let pct = (l["percent"] as? NSNumber)?.doubleValue else { return nil }
                let kind = l["kind"] as? String ?? ""
                let model = ((l["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                let label = kind == "session" ? "Current session"
                    : kind == "weekly_all" ? "Weekly, all models"
                    : model.map { "Weekly, \($0)" } ?? kind.replacingOccurrences(of: "_", with: " ").capitalized
                var row: [String: Any] = ["id": kind + (model ?? ""), "label": label, "percent": pct]
                if let r = epoch(l["resets_at"]) { row["resets_at"] = r }
                return row
            }
        }
        return [("five_hour", "Current session"), ("seven_day", "Weekly, all models")].compactMap { key, label in
            guard let d = j[key] as? [String: Any], let pct = (d["utilization"] as? NSNumber)?.doubleValue else { return nil }
            var row: [String: Any] = ["id": key, "label": label, "percent": pct]
            if let r = epoch(d["resets_at"]) { row["resets_at"] = r }
            return row
        }
    }

    static func save(rows: [[String: Any]], plan: String?) {
        var obj: [String: Any] = ["version": 2, "source": "api", "captured_at": Date().timeIntervalSince1970, "rows": rows]
        if let plan { obj["plan"] = plan }
        if let d = try? JSONSerialization.data(withJSONObject: obj) {
            try? d.write(to: Paths.needsDir.appendingPathComponent("limits-live.json"), options: .atomic)
        }
    }

    // MARK: Process helper

    static func run(_ path: String, _ args: [String], cwd: URL? = nil, env: [String: String]? = nil, timeout: TimeInterval) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        if let env { p.environment = env }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        if done.wait(timeout: .now() + timeout) == .timedOut { p.terminate(); return nil }
        return p.terminationStatus == 0 ? data : nil
    }
}
