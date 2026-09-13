import AppKit

/// Something Clawd can stand on: the visible part of a window's top edge, or the floor.
struct Surface: Equatable {
    static let floorID = 0

    var id: Int
    var y: CGFloat
    var minX: CGFloat
    var maxX: CGFloat
    var windowFrame: CGRect?

    var isFloor: Bool { id == Self.floorID }
    /// The strips of menu bar on each side of the notch.
    var isPerch: Bool { id < 0 }

    func contains(_ x: CGFloat, margin: CGFloat = 0) -> Bool {
        x >= minX - margin && x <= maxX + margin
    }
}

enum ScreenSurfaces {
    /// Walkable edges on the main screen, in coordinates with the origin at its top left.
    /// Window positions are readable without any permission, their contents are never looked at.
    static func current(on screen: NSScreen, ignoring pid: pid_t) -> [Surface] {
        let size = screen.frame.size
        let visible = screen.visibleFrame
        let menuBarBottom = size.height - (visible.maxY - screen.frame.minY)
        let floorY = size.height - (visible.minY - screen.frame.minY)
        var surfaces = [Surface(
            id: Surface.floorID,
            y: floorY,
            minX: visible.minX - screen.frame.minX + 8,
            maxX: visible.maxX - screen.frame.minX - 8,
            windowFrame: nil
        )]

        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return surfaces
        }

        let screenRect = CGRect(origin: .zero, size: size)
        var inFront: [CGRect] = []
        for info in list {
            guard info[kCGWindowLayer as String] as? Int == 0,
                  info[kCGWindowOwnerPID as String] as? pid_t != pid,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  let number = info[kCGWindowNumber as String] as? Int,
                  frame.width >= 160, frame.height >= 80,
                  frame.intersects(screenRect) else { continue }
            defer { inFront.append(frame) }
            guard frame.minY > menuBarBottom + 6, frame.minY < floorY - 40 else { continue }

            // Keep only the parts of the top edge that no window in front is covering.
            var segments: [ClosedRange<CGFloat>] = [max(frame.minX, 0)...min(frame.maxX, size.width)]
            for cover in inFront where cover.minY <= frame.minY + 2 && cover.maxY >= frame.minY {
                segments = segments.flatMap { subtract(cover.minX...cover.maxX, from: $0) }
            }
            for segment in segments where segment.upperBound - segment.lowerBound >= 44 {
                surfaces.append(Surface(id: number, y: frame.minY, minX: segment.lowerBound, maxX: segment.upperBound, windowFrame: frame))
            }
        }
        return surfaces
    }

    private static func subtract(_ cut: ClosedRange<CGFloat>, from range: ClosedRange<CGFloat>) -> [ClosedRange<CGFloat>] {
        guard cut.overlaps(range) else { return [range] }
        var result: [ClosedRange<CGFloat>] = []
        if cut.lowerBound > range.lowerBound {
            result.append(range.lowerBound...cut.lowerBound)
        }
        if cut.upperBound < range.upperBound {
            result.append(cut.upperBound...range.upperBound)
        }
        return result
    }
}
