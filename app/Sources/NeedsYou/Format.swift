import Foundation

enum Fmt {
    static func duration(_ seconds: TimeInterval) -> String {
        let m = max(0, Int(seconds / 60))
        if m < 1 { return "under 1 min" }
        if m < 60 { return "\(m) min" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h) hr" : "\(h) hr \(r) min"
    }

    static func tokens(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        if n < 1_000_000 { return "\(Int((Double(n) / 1000).rounded()))k" }
        return String(format: "%.1fM", Double(n) / 1_000_000)
    }

    static func percent(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }

    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f
    }()
    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; return f
    }()
    static func clockTime(_ d: Date) -> String { clock.string(from: d) }
    static func weekdayTime(_ d: Date) -> String { weekday.string(from: d) }
}
