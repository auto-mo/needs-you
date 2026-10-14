import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let demo: Bool
    private let needs: NeedsStore
    private let usage: UsageStore
    private var item: NSStatusItem!
    private var needsPopover: NSPopover!
    private var usagePopover: NSPopover!
    private var tick = 0
    private var timer: Timer?
    private var icon = StatusIcon.current
    private let dot = NSView()

    init(demo: Bool) {
        self.demo = demo
        needs = NeedsStore(demo: demo)
        usage = UsageStore(demo: demo)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !demo { NeedsStore.ensureDirs(); NeedsStore.writeHeartbeat() }

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = item.button {
            b.image = icon
            b.imagePosition = .imageLeft
            b.target = self
            b.action = #selector(clicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.setAccessibilityLabel("Needs You")
            // Status dot over the icon's top-right corner; a subview so the icon stays a template image.
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3.5
            dot.layer?.borderWidth = 1
            dot.translatesAutoresizingMaskIntoConstraints = false
            b.addSubview(dot)
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 7), dot.heightAnchor.constraint(equalToConstant: 7),
                dot.topAnchor.constraint(equalTo: b.topAnchor, constant: 2),
                dot.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: icon.size.width - 1),
            ])
        }
        needsPopover = makePopover(NeedsPanelView(store: needs))
        usagePopover = makePopover(UsagePanelView(store: usage))

        needs.refresh()
        updateTitle()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func makePopover<V: View>(_ view: V) -> NSPopover {
        let host = NSHostingController(rootView: ThemedRoot { view })
        host.sizingOptions = .preferredContentSize
        let p = NSPopover()
        p.behavior = .transient
        p.animates = false
        p.contentViewController = host
        return p
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let e = NSApp.currentEvent
        let right = e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true
        toggle(right ? usagePopover : needsPopover, other: right ? needsPopover : usagePopover)
    }

    private func toggle(_ pop: NSPopover, other: NSPopover) {
        other.performClose(nil)
        if pop.isShown { pop.performClose(nil); return }
        guard let button = item.button else { return }
        if pop === usagePopover { usage.load() } else { needs.refresh() }
        NSApp.activate(ignoringOtherApps: true)
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        pop.contentViewController?.view.window?.makeKey()
    }

    private func poll() {
        tick += 1
        let open = needsPopover.isShown || usagePopover.isShown
        if !demo, tick % 2 == 0 { NeedsStore.writeHeartbeat() }
        if !demo, tick % 60 == 0 { MemoryCap.check() }
        if open || tick % 3 == 0 {
            needs.refresh()
            if usagePopover.isShown { usage.refreshLimits() }
            updateTitle()
        }
    }

    private func updateTitle() {
        guard let b = item.button else { return }
        let n = needs.permissions.count
        if n > 0 {
            let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            b.attributedTitle = NSAttributedString(string: " \(n)", attributes: [.font: font])
        } else {
            b.attributedTitle = NSAttributedString(string: "")
        }
        let (color, label): (NSColor, String) = switch needs.attention {
        case .permission: (StatusColors.permission, "a permission prompt is waiting")
        case .reply: (StatusColors.reply, "a session is waiting for your reply")
        case .running: (StatusColors.running, "sessions are working")
        case .quiet: (StatusColors.quiet, "nothing needs you")
        }
        dot.layer?.backgroundColor = color.cgColor
        dot.layer?.borderColor = NSColor.black.withAlphaComponent(0.25).cgColor
        b.setAccessibilityLabel("Needs You, \(label)")
    }
}
