import AppKit

enum MenuBarIcon {
    /// Clawd as a template image, so it follows the menu bar appearance.
    static let image: NSImage = {
        let unit: CGFloat = 1
        let size = NSSize(width: 16 * unit + 2, height: 10 * unit + 2)
        let image = NSImage(size: size, flipped: true) { _ in
            let body = Sprite.body + Sprite.legs
            let eyes = Sprite.eyes(for: .idle)
            let path = NSBezierPath()
            for pixel in body {
                path.appendRect(NSRect(x: 1 + pixel.minX * unit, y: 1 + pixel.minY * unit, width: pixel.width * unit, height: pixel.height * unit))
            }
            NSColor.black.setFill()
            path.fill()
            NSGraphicsContext.current?.compositingOperation = .clear
            for eye in eyes {
                NSRect(x: 1 + eye.minX * unit, y: 1 + eye.minY * unit, width: eye.width * unit, height: eye.height * unit).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
