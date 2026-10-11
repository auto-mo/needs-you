import Foundation

enum Paths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var claude: URL { home.appendingPathComponent(".claude") }
    static var sessions: URL { claude.appendingPathComponent("sessions") }
    static var projects: URL { claude.appendingPathComponent("projects") }

    /// Shared protocol folder. Read on every call so tests can change NEEDS_YOU_DIR.
    static var needsDir: URL {
        if let d = ProcessInfo.processInfo.environment["NEEDS_YOU_DIR"], !d.isEmpty {
            return URL(fileURLWithPath: (d as NSString).expandingTildeInPath)
        }
        return claude.appendingPathComponent("needs-you")
    }
    static var configDir: URL { home.appendingPathComponent(".config/needs-you") }
}

func json(_ data: Data) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

func readJSON(_ url: URL) -> [String: Any]? {
    guard let d = try? Data(contentsOf: url) else { return nil }
    return json(d)
}

/// Epoch value in seconds or milliseconds, as Double seconds.
func epochSeconds(_ v: Any?) -> Double? {
    guard let n = (v as? NSNumber)?.doubleValue else { return nil }
    return n > 1e11 ? n / 1000 : n
}
