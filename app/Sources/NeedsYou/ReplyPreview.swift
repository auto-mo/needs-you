import Foundation

/// Last reply text of a session, read from the tail of its transcript. Used when the hook's
/// stop event has no message (sessions that finished before the hook was installed).
@MainActor
final class ReplyPreviewCache {
    private var cache: [String: (mtime: Date, text: String?)] = [:]

    func text(sessionId: String, transcript: String?) -> String? {
        let url: URL
        if let t = transcript, !t.isEmpty {
            url = URL(fileURLWithPath: t)
        } else if let dir = SessionDirectory.projectDir(sessionId: sessionId, transcriptPath: nil) {
            url = dir.appendingPathComponent(sessionId + ".jsonl")
        } else { return nil }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        if let c = cache[url.path], c.mtime == mtime { return c.text }
        let text = Self.lastAssistantText(url)
        cache[url.path] = (mtime, text)
        return text
    }

    static func lastAssistantText(_ url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let window: UInt64 = 1 << 20
        try? fh.seek(toOffset: size > window ? size - window : 0)
        guard let data = try? fh.readToEnd() else { return nil }
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let j = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  j["type"] as? String == "assistant", j["isSidechain"] as? Bool != true,
                  let msg = j["message"] as? [String: Any], let content = msg["content"] as? [[String: Any]] else { continue }
            let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return String(text.prefix(4000)) }
        }
        return nil
    }
}
