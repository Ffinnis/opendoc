#if os(macOS)
import AppKit

enum NativeDockVisibility {
    static let revealDepth: CGFloat = 8
    static let revealDelay: TimeInterval = 0.28

    struct RevealDwell {
        private var enteredAt: TimeInterval?
        mutating func update(isInside: Bool, at time: TimeInterval) -> Bool {
            guard isInside else { reset(); return false }
            guard let enteredAt else { self.enteredAt = time; return false }
            return time - enteredAt >= NativeDockVisibility.revealDelay
        }
        mutating func reset() { enteredAt = nil }
    }

    static func revealArea(_ visible: NSRect, screen: NSRect, edge: String) -> NSRect {
        switch edge {
        case "Left": return NSRect(x: screen.minX, y: visible.minY, width: revealDepth, height: visible.height)
        case "Right": return NSRect(x: screen.maxX - revealDepth, y: visible.minY, width: revealDepth, height: visible.height)
        default: return NSRect(x: visible.minX, y: screen.minY, width: visible.width, height: revealDepth)
        }
    }

    static func activationArea(_ visible: NSRect, screen: NSRect, edge: String) -> NSRect {
        // Include the gap to the screen edge so there is no dead strip during a reveal.
        switch edge {
        case "Left": return NSRect(x: screen.minX, y: visible.minY, width: visible.maxX - screen.minX, height: visible.height)
        case "Right": return NSRect(x: visible.minX, y: visible.minY, width: screen.maxX - visible.minX, height: visible.height)
        default: return NSRect(x: visible.minX, y: screen.minY, width: visible.width, height: visible.maxY - screen.minY)
        }
    }

    static func hiddenFrame(_ visible: NSRect, screen: NSRect, edge: String) -> NSRect {
        var frame = visible
        switch edge {
        case "Left": frame.origin.x = screen.minX - frame.width + 3
        case "Right": frame.origin.x = screen.maxX - 3
        default: frame.origin.y = screen.minY - frame.height + 3
        }
        return frame
    }
}
#endif
