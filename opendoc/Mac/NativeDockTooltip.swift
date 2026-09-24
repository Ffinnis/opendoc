#if os(macOS)
import AppKit

/// Dock labels are shown explicitly because AppKit's delayed tooltip manager
/// does not reliably track nonactivating windows whose hit regions move.
final class NativeDockTooltip: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "")
    var title: String {
        get { label.stringValue }
        set { if label.stringValue != newValue { label.stringValue = newValue } }
    }
    override var fittingSize: NSSize {
        let natural = label.intrinsicContentSize
        return NSSize(width: min(280, max(44, natural.width + 22)), height: natural.height + 12)
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect == .zero ? NSRect(x: 0, y: 0, width: 44, height: 28) : frameRect)
        material = .toolTip
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        label.font = .toolTipsFont(ofSize: 13)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(equalTo: widthAnchor, constant: -22)
        ])
        setAccessibilityIdentifier("dock-hover-label")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A label beside the hovered item on docks without magnification: side
/// docks, Reduce Motion, and overflowing rows. It never takes pointer events
/// and is attached to the dock only while shown, so it follows auto-hide.
@MainActor
final class NativeDockHoverLabel {
    private let panel: DesktopDockPanel
    private let tooltip = NativeDockTooltip()
    private weak var parent: NSWindow?
    private(set) var itemID: UUID?

    init() {
        panel = DesktopDockPanel(contentRect: NSRect(x: 0, y: 0, width: 44, height: 28), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Dock Label"
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = tooltip
    }

    var isShown: Bool { panel.isVisible }

    /// `anchor` is the item's frame in screen coordinates.
    func show(_ title: String, itemID: UUID, anchor: NSRect, edge: String, in parent: NSWindow) {
        guard !title.isEmpty else { hide(); return }
        tooltip.title = title
        let size = tooltip.fittingSize
        let gap: CGFloat = 8
        let origin: NSPoint
        switch edge {
        case "Left": origin = NSPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
        case "Right": origin = NSPoint(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2)
        default: origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
        }
        var frame = NSRect(origin: origin, size: size)
        if let screen = parent.screen?.visibleFrame {
            frame.origin.x = min(max(screen.minX + 4, frame.minX), screen.maxX - size.width - 4)
            frame.origin.y = min(max(screen.minY + 4, frame.minY), screen.maxY - size.height - 4)
        }
        panel.appearance = parent.contentView?.effectiveAppearance
        panel.setFrame(frame, display: true)
        if self.parent !== parent || panel.parent == nil {
            self.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
            self.parent = parent
        }
        self.itemID = itemID
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        itemID = nil
        guard panel.isVisible || panel.parent != nil else { return }
        parent?.removeChildWindow(panel)
        parent = nil
        panel.orderOut(nil)
    }
}
#endif
