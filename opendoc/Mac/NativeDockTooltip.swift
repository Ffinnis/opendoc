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
        layer?.cornerRadius = 7
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
#endif
