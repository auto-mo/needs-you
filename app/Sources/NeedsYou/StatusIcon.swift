import AppKit

/// Status item and header mark. A user-supplied icon wins; otherwise a generic speech bubble
/// with a dot, drawn at runtime (deliberately not any vendor's logo).
enum StatusIcon {
    static let height: CGFloat = 18

    /// True for --demo and --render-screenshots, so published screenshots never show a personal icon.
    static var useDefault = false
    static var current: NSImage = load()

    static func load() -> NSImage {
        if useDefault { return drawn() }
        let dir = Paths.configDir
        let one = dir.appendingPathComponent("icon.png"), two = dir.appendingPathComponent("icon@2x.png")
        let reps = [two, one].compactMap { (try? Data(contentsOf: $0)).flatMap(NSBitmapImageRep.init(data:)) }
        guard let first = reps.first else { return drawn() }
        // Point size from the @2x pixels; only scale down if the icon is taller than the menu bar allows.
        var size = NSSize(width: CGFloat(first.pixelsWide) / 2, height: CGFloat(first.pixelsHigh) / 2)
        if size.height > height { size = NSSize(width: size.width * height / size.height, height: height) }
        let img = NSImage(size: size)
        reps.forEach(img.addRepresentation)
        img.isTemplate = true
        return img
    }

    static func drawn() -> NSImage {
        let size = NSSize(width: height, height: height)
        let img = NSImage(size: size, flipped: false) { _ in
            let bubble = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 5, width: 15, height: 11), xRadius: 4.5, yRadius: 4.5)
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: 4.5, y: 6)); tail.line(to: NSPoint(x: 4, y: 1.5)); tail.line(to: NSPoint(x: 9, y: 5.5)); tail.close()
            NSColor.black.setFill()
            bubble.fill(); tail.fill()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 7, y: 8.5, width: 4, height: 4)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}
