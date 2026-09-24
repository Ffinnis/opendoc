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
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        label.font = .systemFont(ofSize: 12.5, weight: .medium)
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

    /// Fading out still counts as hidden, so a new item shows immediately.
    var isShown: Bool { panel.isVisible && itemID != nil }
    private var generation = 0
    private var fadingOut = false

    /// `anchor` is the item's frame in screen coordinates.
    func show(_ title: String, itemID: UUID, anchor: NSRect, edge: String, in parent: NSWindow) {
        guard !title.isEmpty else { hide(); return }
        tooltip.title = title
        let size = tooltip.fittingSize
        let gap = NativeDockStyle.labelGap
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
        generation += 1
        // The model alpha already reads 0 or 1 during a fade, so track the
        // fade itself: a label shown while fading out must fade back in.
        if !panel.isVisible || fadingOut {
            if !panel.isVisible { panel.alphaValue = 0; panel.orderFrontRegardless() }
            fadingOut = false
            NativeMotion.animate(0.12) { panel.animator().alphaValue = 1 }
        }
    }

    func hide() {
        itemID = nil
        guard !fadingOut, panel.isVisible || panel.parent != nil else { return }
        fadingOut = true
        generation += 1
        let current = generation
        NativeMotion.animate(0.1) { panel.animator().alphaValue = 0 } completion: { [weak self] in
            // A label shown again during the fade keeps its window.
            guard let self, self.generation == current else { return }
            self.fadingOut = false
            self.parent?.removeChildWindow(self.panel)
            self.parent = nil
            self.panel.orderOut(nil)
        }
    }
}
#endif
