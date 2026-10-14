import Foundation

enum UsageRange: String, CaseIterable { case today = "Today", week = "This week" }

struct PartUsage: Identifiable {
    let id: String
    let title: String          // "Main conversation" or "Sub-agent: ..."
    let model: String          // display name
    let share: Double          // of the session's cost
    let subtitle: String
    let cost: Double
}

struct SessionUsage: Identifiable {
    let id: String
    let name: String
    let cost: Double
    let share: Double
    let tokens: Int
    let parts: [PartUsage]
    let heavy: [(label: String, share: Double)]
    let subAgentCount: Int
}

struct UsageSnapshot {
    var sessions: [SessionUsage] = []
    var total: Double = 0
}

private struct Tokens {
    var input = 0, output = 0, cache5m = 0, cache1h = 0, read = 0
    var total: Int { input + output + cache5m + cache1h + read }
    var cacheCreation: Int { cache5m + cache1h }
}

private struct Reply {
    var ts: Double
    var model: String
    var tokens: Tokens
    var cats: [String]
    var tools: Int
    var context: Int

    var cost: Double {
        let p = Pricing.price(for: model)
        let m = 1_000_000.0
        return (Double(tokens.input) * p.input + Double(tokens.output) * p.output
                + Double(tokens.cache5m) * p.input * 1.25 + Double(tokens.cache1h) * p.input * 2.0
                + Double(tokens.read) * p.read) / m
    }
}

/// Parsed state of one transcript file. Kept between scans so only appended bytes are read.
private final class FileAgg {
    var offset: UInt64 = 0
    var size: UInt64 = 0
    var mtime = Date.distantPast
    var replies: [String: Reply] = [:]
    var toolNames: [String: String] = [:]
    var pendingCats: [String] = []
    var rawAssistantLines = 0
    var cwd: String?
}

struct ScanStats { var rawAssistantLines = 0; var uniqueReplies = 0 }

actor UsageScanner {
    static let shared = UsageScanner()

    private var cache: [String: FileAgg] = [:]
    private(set) var statsBySession: [String: ScanStats] = [:]

    private struct FileRef {
        let url: URL
        let sessionId: String
        let projectDir: URL
        let agentId: String?
    }

    // MARK: Snapshot

    func snapshot(range: UsageRange, now: Date = Date()) -> UsageSnapshot {
        let start = range == .today ? Calendar.current.startOfDay(for: now) : now.addingTimeInterval(-7 * 86400)
        let startTs = start.timeIntervalSince1970
        var bySession: [String: [(FileRef, FileAgg)]] = [:]
        var stats: [String: ScanStats] = [:]

        for ref in enumerate(modifiedAfter: start) {
            let agg = update(ref.url)
            bySession[ref.sessionId, default: []].append((ref, agg))
            let inWindow = agg.replies.values.filter { $0.ts >= startTs }.count
            var s = stats[ref.sessionId, default: ScanStats()]
            s.rawAssistantLines += agg.rawAssistantLines
            s.uniqueReplies += inWindow
            stats[ref.sessionId] = s
        }
        statsBySession = stats

        var sessions: [SessionUsage] = []
        for (sid, files) in bySession {
            if let s = build(sessionId: sid, files: files, startTs: startTs) { sessions.append(s) }
        }
        let total = sessions.reduce(0) { $0 + $1.cost }
        guard total > 0 else { return UsageSnapshot() }
        sessions = sessions.map { s in
            SessionUsage(id: s.id, name: s.name, cost: s.cost, share: s.cost / total, tokens: s.tokens,
                         parts: s.parts, heavy: s.heavy, subAgentCount: s.subAgentCount)
        }.sorted { $0.cost > $1.cost }
        return UsageSnapshot(sessions: sessions, total: total)
    }

    private func enumerate(modifiedAfter start: Date) -> [FileRef] {
        let fm = FileManager.default
        var out: [FileRef] = []
        func fresh(_ u: URL) -> Bool {
            guard let m = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return false }
            return m >= start
        }
        for dir in (try? fm.contentsOfDirectory(at: Paths.projects, includingPropertiesForKeys: nil)) ?? [] {
            if dir.lastPathComponent.hasSuffix("needs-you-refresh") { continue }  // the app's own sign-in refresh
            for item in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                if item.pathExtension == "jsonl" {
                    if fresh(item) { out.append(FileRef(url: item, sessionId: item.deletingPathExtension().lastPathComponent, projectDir: dir, agentId: nil)) }
                } else {
                    let subs = item.appendingPathComponent("subagents")
                    for f in (try? fm.contentsOfDirectory(at: subs, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "jsonl" && fresh(f) {
                        out.append(FileRef(url: f, sessionId: item.lastPathComponent, projectDir: dir, agentId: f.deletingPathExtension().lastPathComponent))
                    }
                }
            }
        }
        return out
    }

    // MARK: Aggregation

    private func build(sessionId: String, files: [(FileRef, FileAgg)], startTs: Double) -> SessionUsage? {
        var parts: [PartUsage] = []
        var partCosts: [(PartUsage, Double)] = []
        var heavy: [String: Double] = [:]
        var tokens = 0
        var cwd: String?
        let projectDir = files.first?.0.projectDir

        for (ref, agg) in files {
            let replies = agg.replies.values.filter { $0.ts >= startTs }
            guard !replies.isEmpty else { continue }
            if ref.agentId == nil { cwd = agg.cwd ?? cwd } else { cwd = cwd ?? agg.cwd }
            var cost = 0.0, maxCtx = 0, tools = 0
            var modelCost: [String: Double] = [:]
            for r in replies {
                let c = r.cost
                cost += c; tokens += r.tokens.total; tools += r.tools
                maxCtx = max(maxCtx, r.context)
                modelCost[r.model, default: 0] += c
                if !r.cats.isEmpty {
                    let each = Double(r.tokens.cacheCreation) / Double(r.cats.count)
                    for cat in r.cats { heavy[cat, default: 0] += each }
                }
            }
            let model = Pricing.displayName(modelCost.max { $0.value < $1.value }?.key ?? "")
            if let agentId = ref.agentId {
                let meta = readJSON(ref.url.deletingLastPathComponent().appendingPathComponent(agentId + ".meta.json")) ?? [:]
                let desc = meta["description"] as? String ?? agentId
                let type = meta["agentType"] as? String ?? "sub-agent"
                let p = PartUsage(id: agentId, title: "Sub-agent: \(desc)", model: model, share: 0,
                                  subtitle: "\(type), \(tools) tool calls", cost: cost)
                partCosts.append((p, cost))
            } else {
                let p = PartUsage(id: "main", title: "Main conversation", model: model, share: 0,
                                  subtitle: "\(replies.count) replies, longest context \(Fmt.tokens(maxCtx)) tokens", cost: cost)
                partCosts.append((p, cost))
            }
        }
        let total = partCosts.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        parts = partCosts.map { p, c in
            PartUsage(id: p.id, title: p.title, model: p.model, share: c / total, subtitle: p.subtitle, cost: c)
        }.sorted { ($0.id == "main" ? 1 : 0, $0.cost) > ($1.id == "main" ? 1 : 0, $1.cost) }

        let heavyTotal = heavy.values.reduce(0, +)
        let top = heavy.sorted { $0.value > $1.value }.prefix(3).map { (label: $0.key, share: heavyTotal > 0 ? $0.value / heavyTotal : 0) }
        let name = SessionDirectory.resolveName(sessionId: sessionId, cwd: cwd, sessionName: liveName(sessionId), projectDir: projectDir)
        return SessionUsage(id: sessionId, name: name, cost: total, share: 0, tokens: tokens, parts: parts, heavy: top,
                            subAgentCount: parts.filter { $0.id != "main" }.count)
    }

    private func liveName(_ sid: String) -> String? {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Paths.sessions, includingPropertiesForKeys: nil)) ?? []
        for u in urls where u.pathExtension == "json" {
            if let j = readJSON(u), j["sessionId"] as? String == sid, let n = j["name"] as? String { return n }
        }
        return nil
    }

    // MARK: Incremental file parsing

    private func update(_ url: URL) -> FileAgg {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        let mtime = attrs?[.modificationDate] as? Date ?? .distantPast
        var agg = cache[url.path] ?? FileAgg()
        if size < agg.offset { agg = FileAgg() }          // truncated or rewritten
        if size == agg.offset && mtime == agg.mtime { return agg }
        agg.mtime = mtime; agg.size = size
        cache[url.path] = agg

        guard let h = try? FileHandle(forReadingFrom: url) else { return agg }
        defer { try? h.close() }
        try? h.seek(toOffset: agg.offset)
        var carry = Data()
        let chunk = 4 * 1024 * 1024
        var more = true
        while more { autoreleasepool {  // each 4 MB read is released before the next
            let data = (try? h.read(upToCount: chunk)) ?? Data()
            if data.isEmpty { more = false; return }
            carry.append(data)
            var lineStart = carry.startIndex
            while let nl = carry[lineStart...].firstIndex(of: 0x0A) {
                // Drain each line's temporary objects now; a background thread has no pool that empties
                // until the scan ends, which pushed memory past 500 MB on a week of transcripts.
                autoreleasepool { ingest(Data(carry[lineStart..<nl]), into: agg) }
                lineStart = carry.index(after: nl)
            }
            agg.offset += UInt64(lineStart - carry.startIndex)
            carry = Data(carry[lineStart...])
        } }
        return agg
    }

    private static let assistantMark = Data("\"assistant\"".utf8)
    private static let resultMark = Data("tool_result".utf8)
    private static let imageMark = Data("\"type\":\"image\"".utf8)
    private static let idMark = Data("\"tool_use_id\":\"".utf8)

    private static func toolUseIds(_ line: Data) -> [String] {
        var ids: [String] = []
        var from = line.startIndex
        while let r = line.range(of: idMark, in: from..<line.endIndex),
              let end = line[r.upperBound...].firstIndex(of: 0x22) {
            ids.append(String(decoding: line[r.upperBound..<end], as: UTF8.self))
            from = end
        }
        return ids
    }
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    private func ingest(_ line: Data, into agg: FileAgg) {
        let isAssistant = line.range(of: Self.assistantMark) != nil
        let isResult = !isAssistant && line.range(of: Self.resultMark) != nil
        // Big tool results are mostly screenshots or long output; read what's needed without decoding them.
        if isResult && line.count > 64 * 1024 {
            let image = line.range(of: Self.imageMark) != nil
            for id in Self.toolUseIds(line) {
                agg.pendingCats.append(image ? "Screenshots" : Self.category(name: agg.toolNames[id] ?? ""))
            }
            return
        }
        guard isAssistant || isResult, let obj = json(line) else { return }
        if agg.cwd == nil, let c = obj["cwd"] as? String { agg.cwd = c }
        let type = obj["type"] as? String
        guard let message = obj["message"] as? [String: Any] else { return }
        let blocks = message["content"] as? [[String: Any]] ?? []

        if type == "user" {
            for b in blocks where b["type"] as? String == "tool_result" {
                agg.pendingCats.append(Self.category(for: b, names: agg.toolNames))
            }
            return
        }
        guard type == "assistant" else { return }
        agg.rawAssistantLines += 1
        var tools = 0
        for b in blocks where b["type"] as? String == "tool_use" {
            tools += 1
            if let id = b["id"] as? String, let n = b["name"] as? String { agg.toolNames[id] = n }
        }
        guard let usage = message["usage"] as? [String: Any], let model = message["model"] as? String, model != "<synthetic>",
              let tsText = obj["timestamp"] as? String,
              let date = Self.iso.date(from: tsText) ?? Self.isoPlain.date(from: tsText) else { return }

        func n(_ d: [String: Any], _ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
        var t = Tokens()
        t.input = n(usage, "input_tokens"); t.output = n(usage, "output_tokens"); t.read = n(usage, "cache_read_input_tokens")
        if let cc = usage["cache_creation"] as? [String: Any], cc["ephemeral_5m_input_tokens"] != nil || cc["ephemeral_1h_input_tokens"] != nil {
            t.cache5m = n(cc, "ephemeral_5m_input_tokens"); t.cache1h = n(cc, "ephemeral_1h_input_tokens")
        } else {
            t.cache5m = n(usage, "cache_creation_input_tokens")
        }
        let key = obj["requestId"] as? String ?? message["id"] as? String ?? (obj["uuid"] as? String ?? UUID().uuidString)
        let ctx = t.input + t.read + t.cacheCreation
        if var existing = agg.replies[key] {
            existing.ts = date.timeIntervalSince1970; existing.model = model; existing.tokens = t
            existing.tools += tools; existing.context = max(existing.context, ctx)
            agg.replies[key] = existing
        } else {
            agg.replies[key] = Reply(ts: date.timeIntervalSince1970, model: model, tokens: t, cats: agg.pendingCats,
                                     tools: tools, context: ctx)
            agg.pendingCats = []
        }
    }

    private static func category(for result: [String: Any], names: [String: String]) -> String {
        if let parts = result["content"] as? [[String: Any]], parts.contains(where: { $0["type"] as? String == "image" }) {
            return "Screenshots"
        }
        return category(name: names[result["tool_use_id"] as? String ?? ""] ?? "")
    }

    private static func category(name: String) -> String {
        switch name {
        case "Bash": return "Shell output"
        case "Read": return "File reads"
        case "WebFetch", "WebSearch": return "Web"
        case "Agent", "Task": return "Sub-agent results"
        default:
            if name.hasPrefix("mcp__") { return name.lowercased().contains("browser") ? "Browser" : "Other MCP" }
            return "Other"
        }
    }
}
