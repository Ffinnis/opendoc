#if os(macOS)
import AppKit

/// Building blocks for widget and folder cards: a coloured header, capsule
/// buttons, a large progress ring and grouped panels.
enum NativeCard {
    static let width: CGFloat = 340
    static let inset: CGFloat = 20
    static let spacing: CGFloat = 14

    static func title(_ string: String, size: CGFloat = 15) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.font = .systemFont(ofSize: size, weight: .semibold)
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    static func caption(_ string: String, size: CGFloat = 11.5) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: string)
        field.font = .systemFont(ofSize: size)
        field.textColor = .secondaryLabelColor
        return field
    }

    static func value(_ size: CGFloat = 34) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = NativeDockStyle.valueFont(size)
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    static func row(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = spacing
        stack.alignment = .centerY
        return stack
    }

    static func column(_ views: [NSView], spacing: CGFloat = 6, alignment: NSLayoutConstraint.Attribute = .leading) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = spacing
        stack.alignment = alignment
        return stack
    }

    /// A small secondary label above a control, for forms inside cards.
    static func labeled(_ label: String, _ control: NSView) -> NSStackView {
        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.textColor = .secondaryLabelColor
        let group = column([title, control], spacing: 5)
        control.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        return group
    }
}

/// The top of every card: the widget's glyph on a tinted badge, its name and
/// a short description of what it shows.
final class NativeCardHeader: NSStackView {
    private let badge = NativeCardBadge()
    let titleField = NativeCard.title("")
    let subtitleField = NSTextField(labelWithString: "")

    init(symbol: String, color: NSColor, title: String, subtitle: String) {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 10
        alignment = .centerY
        badge.symbol = symbol
        badge.color = color
        titleField.stringValue = title
        subtitleField.stringValue = subtitle
        subtitleField.font = .systemFont(ofSize: 11)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail
        let text = NativeCard.column([titleField, subtitleField], spacing: 1)
        addArrangedSubview(badge)
        addArrangedSubview(text)
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

final class NativeCardBadge: NSView {
    var symbol = "square" { didSet { needsDisplay = true } }
    var color: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 32, height: 32) }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        color.withAlphaComponent(dark ? 0.26 : 0.16).setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        path.fill()
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        let size = image.size
        image.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

/// A capsule button: filled with the widget colour for the main action,
/// a quiet fill for the others.
final class NativeCapsuleButton: NSButton {
    enum Style { case primary(NSColor), secondary }
    private let handler: () -> Void
    private let style: Style

    init(_ title: String, style: Style = .secondary, handler: @escaping () -> Void) {
        self.handler = handler
        self.style = style
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .exterior
        target = self; action = #selector(invoke)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func invoke() { handler() }

    override var intrinsicContentSize: NSSize {
        let size = (title as NSString).size(withAttributes: [.font: font()])
        return NSSize(width: ceil(size.width) + 30, height: 28)
    }
    private func font() -> NSFont { .systemFont(ofSize: 13, weight: .medium) }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        let fill: NSColor
        let text: NSColor
        switch style {
        case .primary(let color): fill = color; text = NativeCapsuleButton.label(on: color)
        case .secondary: fill = NSColor.labelColor.withAlphaComponent(0.09); text = .labelColor
        }
        let alpha: CGFloat = !isEnabled ? 0.4 : isHighlighted ? 0.75 : 1
        fill.withAlphaComponent(fill.alphaComponent * alpha).setFill()
        path.fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font(), .foregroundColor: text.withAlphaComponent(isEnabled ? 1 : 0.5), .paragraphStyle: paragraph]
        let height = (title as NSString).size(withAttributes: attributes).height
        (title as NSString).draw(in: NSRect(x: 10, y: (bounds.height - height) / 2, width: bounds.width - 20, height: height), withAttributes: attributes)
    }
    override var isFlipped: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }

    /// White on deep colours, near-black on light ones such as yellow or cyan.
    static func label(on color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return .white }
        func linear(_ value: CGFloat) -> CGFloat { value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        return luminance > 0.4 ? NSColor(calibratedWhite: 0.1, alpha: 1) : .white
    }
}

/// A large timer ring with the remaining time inside it.
final class NativeCardRing: NSView {
    var fraction: Double = 0 { didSet { if fraction != oldValue { needsDisplay = true } } }
    var color: NSColor = .systemOrange { didSet { needsDisplay = true } }
    let valueField = NativeCard.value(30)
    let statusField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        valueField.alignment = .center
        statusField.alignment = .center
        statusField.font = .systemFont(ofSize: 11, weight: .medium)
        statusField.textColor = .secondaryLabelColor
        statusField.lineBreakMode = .byTruncatingTail
        // Text stays inside the ring's opening.
        for field in [valueField, statusField] {
            field.widthAnchor.constraint(lessThanOrEqualToConstant: 124).isActive = true
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let stack = NativeCard.column([valueField, statusField], spacing: 0, alignment: .centerX)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: 148),
            heightAnchor.constraint(equalToConstant: 148)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let width: CGFloat = 9
        let rect = bounds.insetBy(dx: width / 2 + 1, dy: width / 2 + 1)
        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = width
        NSColor.labelColor.withAlphaComponent(0.1).setStroke(); track.stroke()
        guard fraction > 0 else { return }
        let arc = NSBezierPath()
        arc.lineWidth = width; arc.lineCapStyle = .round
        arc.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                      startAngle: -90, endAngle: -90 + 360 * CGFloat(min(1, fraction)), clockwise: false)
        color.setStroke(); arc.stroke()
    }
}

/// A thin rounded progress bar in a widget's colour.
final class NativeCardBar: NSView {
    var fraction: Double = 0 { didSet { if fraction != oldValue { needsDisplay = true } } }
    var color: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 6) }
    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        guard fraction > 0 else { return }
        color.setFill()
        let width = max(bounds.height, bounds.width * CGFloat(min(1, fraction)))
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: bounds.height), xRadius: radius, yRadius: radius).fill()
    }
}

/// A row of glasses for the hydration card, filled up to today's count.
final class NativeCardGlasses: NSView {
    var count = 0 { didSet { if count != oldValue { needsDisplay = true } } }
    var goal = 8
    var color: NSColor = .systemCyan
    override var intrinsicContentSize: NSSize { NSSize(width: CGFloat(goal) * 30, height: 26) }
    override func draw(_ dirtyRect: NSRect) {
        for index in 0..<goal {
            let filled = index < count
            let configuration = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [filled ? color : NSColor.labelColor.withAlphaComponent(0.18)]))
            guard let image = NSImage(systemSymbolName: filled ? "drop.fill" : "drop", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else { continue }
            let size = image.size
            let x = CGFloat(index) * 30 + (30 - size.width) / 2
            image.draw(in: NSRect(x: x, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
        }
    }
}

/// A grouped panel inside a card, like an inset list in System Settings.
final class NativeCardGroup: NSView {
    let stack = NSStackView()
    init(_ views: [NSView], spacing: CGFloat = 10, padding: CGFloat = 12) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding)
        ])
        for view in views {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.04)).cgColor
    }
}
#endif
