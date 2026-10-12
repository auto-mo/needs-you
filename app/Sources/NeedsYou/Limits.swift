import Foundation

struct LimitRow: Identifiable {
    let id: String
    let label: String
    let percent: Double      // 0...100
    let resets: Date?
}

struct LimitsInfo {
    var rows: [LimitRow]
    var capturedAt: Date?
    var plan: String?
}

/// Defensive reader: the rate_limits shape is not guaranteed.
enum LimitsReader {
    static func read() -> LimitsInfo? {
        guard let j = readJSON(Paths.needsDir.appendingPathComponent("limits.json")),
              let rl = j["rate_limits"] as? [String: Any] else { return nil }
        var rows: [LimitRow] = []
        for key in orderedKeys(Array(rl.keys)) {
            guard let d = rl[key] as? [String: Any], let pct = percent(d) else { continue }
            rows.append(LimitRow(id: key, label: label(key), percent: min(max(pct, 0), 100), resets: resetDate(d)))
        }
        var plan: String?
        for src in [j, rl] {
            for k in ["plan", "plan_name", "subscription_type", "tier"] {
                if let s = src[k] as? String, !s.isEmpty { plan = s.capitalized; break }
            }
        }
        if let p = plan, !p.lowercased().contains("plan") { plan = p + " plan" }
        return LimitsInfo(rows: rows, capturedAt: epochSeconds(j["captured_at"]).map { Date(timeIntervalSince1970: $0) }, plan: plan)
    }

    private static func orderedKeys(_ keys: [String]) -> [String] {
        func rank(_ k: String) -> Int { k == "five_hour" ? 0 : k == "seven_day" ? 1 : k.hasPrefix("seven_day") ? 2 : 3 }
        return keys.sorted { (rank($0), $0) < (rank($1), $1) }
    }

    static func label(_ key: String) -> String {
        func title(_ s: String) -> String { s.split(separator: "_").map { $0.capitalized }.joined(separator: " ") }
        if key == "five_hour" { return "Current session" }
        if key == "seven_day" { return "Weekly, all models" }
        if key.hasPrefix("seven_day_") { return "Weekly, " + title(String(key.dropFirst("seven_day_".count))) }
        return title(key)
    }

    private static func percent(_ d: [String: Any]) -> Double? {
        for k in ["used_percentage", "used_percent", "percent_used"] {
            if let n = (d[k] as? NSNumber)?.doubleValue { return n }
        }
        // `utilization` may be a 0-1 fraction or 0-100.
        if let n = (d["utilization"] as? NSNumber)?.doubleValue { return n <= 1 ? n * 100 : n }
        return nil
    }

    private static func resetDate(_ d: [String: Any]) -> Date? {
        for k in ["resets_at", "reset_at"] {
            if let s = d[k] as? String {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let x = f.date(from: s) { return x }
                f.formatOptions = [.withInternetDateTime]
                if let x = f.date(from: s) { return x }
            }
            if let e = epochSeconds(d[k]) { return Date(timeIntervalSince1970: e) }
        }
        return nil
    }

    static func resetText(_ d: Date?, now: Date = Date()) -> String? {
        guard let d else { return nil }
        let s = d.timeIntervalSince(now)
        if s <= 0 { return "reset at " + Fmt.clockTime(d) }
        if s < 86400 { return "resets in " + Fmt.duration(s) }
        return "resets " + Fmt.weekdayTime(d)
    }
}
