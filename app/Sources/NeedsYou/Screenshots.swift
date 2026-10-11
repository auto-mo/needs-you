import AppKit
import SwiftUI

/// Renders both panels with demo data to PNGs (light and dark) without needing screen recording.
@MainActor
enum Screenshots {
    /// True while rendering offscreen; AppKit-backed controls (text fields) can't be drawn then.
    static var active = false

    static func render(to outDir: String) {
        active = true
        let dir = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let tag = scheme == .light ? "light" : "dark"
            save(NeedsPanelView(store: NeedsStore(demo: true), scrollable: false), scheme, dir.appendingPathComponent("needs-you-\(tag).png"))
            save(UsagePanelView(store: UsageStore(demo: true), scrollable: false), scheme, dir.appendingPathComponent("usage-\(tag).png"))
        }
    }

    /// Renders the Needs you panel from the real data on this Mac, for checking it by eye.
    static func renderLive(to outDir: String) {
        let dir = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = NeedsStore()
        store.refresh()
        save(NeedsPanelView(store: store, scrollable: false), .light, dir.appendingPathComponent("live-needs-you.png"))
    }

    /// One expanded message, to check the Markdown rendering by eye.
    static func renderMessage(to outDir: String, text: String) {
        let dir = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            save(MessageBox(text: text, maxHeight: 5000, startExpanded: true).padding(12).frame(width: 380), scheme,
                 dir.appendingPathComponent("message-\(scheme == .light ? "light" : "dark").png"))
        }
    }

    private static func save<V: View>(_ view: V, _ scheme: ColorScheme, _ url: URL) {
        let framed = ThemedRoot { view }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.gray.opacity(0.3), lineWidth: 1))
            .padding(1)
            .environment(\.colorScheme, scheme)
        let r = ImageRenderer(content: framed)
        r.scale = 2
        guard let cg = r.cgImage else { print("render failed: \(url.lastPathComponent)"); return }
        let rep = NSBitmapImageRep(cgImage: cg)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print("wrote \(url.path) (\(cg.width)x\(cg.height))")
        }
    }
}
