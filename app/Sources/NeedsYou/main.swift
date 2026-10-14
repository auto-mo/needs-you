import AppKit

let args = CommandLine.arguments

MainActor.assumeIsolated {
    StatusIcon.useDefault = args.contains("--demo") || args.contains("--render-screenshots")
    if let i = args.firstIndex(of: "--render-screenshots") {
        _ = NSApplication.shared
        Screenshots.render(to: i + 1 < args.count ? args[i + 1] : "screenshots")
        exit(0)
    }
    if let i = args.firstIndex(of: "--render-live") {
        _ = NSApplication.shared
        Screenshots.renderLive(to: i + 1 < args.count ? args[i + 1] : "live")
        exit(0)
    }
    if let i = args.firstIndex(of: "--render-message"), i + 2 < args.count {
        _ = NSApplication.shared
        Screenshots.renderMessage(to: args[i + 1], text: (try? String(contentsOfFile: args[i + 2], encoding: .utf8)) ?? "")
        exit(0)
    }
    if args.contains("--renew-signin") {  // check the sign-in renewal path on its own
        print("claude:", LiveLimits.claudePath() ?? "not found")
        let before = LiveLimits.readCredential()?.expires
        LiveLimits.renewSignIn()
        print("expiry before:", before.map { "\($0)" } ?? "-", "after:", LiveLimits.readCredential().map { "\($0.expires)" } ?? "-")
        exit(0)
    }
    if args.contains("--fetch-limits") {  // check the live limits path; prints labels and numbers only
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await LiveLimits.shared.refresh(force: true)
            if let e = await LiveLimits.shared.lastError { print("error:", e) }
            for r in LimitsReader.read()?.rows ?? [] { print(r.label, Int(r.percent), LimitsReader.resetText(r.resets) ?? "") }
            print("live:", LimitsReader.read()?.live ?? false, "plan:", LimitsReader.read()?.plan ?? "-")
            done.signal()
        }
        done.wait()
        exit(0)
    }
    if args.contains("--check") {
        _ = NSApplication.shared
        SelfCheck.run()
        exit(0)
    }

    // One copy only: the login item and a manual open must not give two icons.
    if let id = Bundle.main.bundleIdentifier,
       NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
        exit(0)
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate(demo: args.contains("--demo"))
    app.delegate = delegate
    app.run()
}
