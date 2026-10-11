import Foundation

struct Price { let input: Double; let output: Double; let read: Double }

/// $/M tokens, matched by longest model-id prefix. Bundled pricing.json overrides the built-ins.
enum Pricing {
    private static let fallback = Price(input: 3, output: 15, read: 0.3)

    private static let table: [(String, Price)] = {
        var raw: [String: Any] = [:]
        if let p = Bundle.main.path(forResource: "pricing", ofType: "json"),
           let d = FileManager.default.contents(atPath: p), let j = json(d) { raw = j }
        if raw.isEmpty { raw = builtin }
        var out: [(String, Price)] = []
        for (k, v) in raw {
            guard let d = v as? [String: Any], let i = (d["in"] as? NSNumber)?.doubleValue,
                  let o = (d["out"] as? NSNumber)?.doubleValue, let r = (d["read"] as? NSNumber)?.doubleValue else { continue }
            out.append((k, Price(input: i, output: o, read: r)))
        }
        return out.sorted { $0.0.count > $1.0.count }
    }()

    private static let builtin: [String: Any] = [
        "claude-fable-5": ["in": 10, "out": 50, "read": 1.0], "claude-fable-5-1": ["in": 10, "out": 50, "read": 0.25],
        "claude-mythos-5": ["in": 10, "out": 50, "read": 1.0], "claude-opus-5-5": ["in": 4, "out": 20, "read": 0.2],
        "claude-opus-5": ["in": 5, "out": 25, "read": 0.5], "claude-opus-4": ["in": 5, "out": 25, "read": 0.5],
        "claude-sonnet-5": ["in": 2, "out": 10, "read": 0.2], "claude-sonnet-4": ["in": 3, "out": 15, "read": 0.3],
        "claude-haiku-5-5": ["in": 0.1, "out": 0.5, "read": 0.01], "claude-haiku-4": ["in": 1, "out": 5, "read": 0.1],
    ]

    static func price(for model: String) -> Price {
        table.first { $0.0 != "default" && model.hasPrefix($0.0) }?.1
            ?? table.first { $0.0 == "default" }?.1 ?? fallback
    }

    /// "claude-opus-5-5-20261001" -> "Opus 5.5"
    static func displayName(_ model: String) -> String {
        var parts = model.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        guard let family = parts.first else { return model }
        var version: [String] = []
        for p in parts.dropFirst() {
            guard p.count <= 2, Int(p) != nil else { break }
            version.append(p)
        }
        return ([family.capitalized] + (version.isEmpty ? [] : [version.joined(separator: ".")])).joined(separator: " ")
    }
}
