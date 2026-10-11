import AppKit

/// Menu bar dot, most urgent first. Red and yellow mean you are needed; blue means work is
/// running; green means all quiet.
enum StatusColors {
    static let permission = NSColor(srgbRed: 0.90, green: 0.28, blue: 0.24, alpha: 1)  // red: approve or deny
    static let reply = NSColor(srgbRed: 0.96, green: 0.72, blue: 0.10, alpha: 1)       // yellow: waiting for your reply
    static let running = NSColor(srgbRed: 0.23, green: 0.51, blue: 0.96, alpha: 1)     // blue: working
    static let quiet = NSColor(srgbRed: 0.19, green: 0.64, blue: 0.42, alpha: 1)       // green: nothing needs you
}
