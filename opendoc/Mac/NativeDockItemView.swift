#if os(macOS)
import AppKit
import IOKit.ps
import QuartzCore

final class NativeDockItemView: FlippedNativeView {
    var item: DockItem { didSet { runningCount = NativeApplications.runningCount(item); if item.kind == .folder || item.kind != oldValue.kind || item.url != oldValue.url { icon = NativeApplications.icon(for: item); updateArtwork() }; toolTip = item.title; setAccessibilityLabel(item.title); updateBackground(); lastRefreshBucket = nil; refreshIfNeeded(at: Date()); canvas.needsDisplay = true } }
    let iconSize: CGFloat
    let vertical: Bool
    weak var controller: NativeDockController?
    private var pressAmount: CGFloat = 0
    private var runningCount = 0
    private var lastRefreshBucket: Int?
    private var dataReading = NativeWidgetData.Reading(value: "…", detail: "Loading…")
    private var customReading = NativeCustomWidgetData.Reading()
    private var dragging = false
    private var dragStart = NSPoint.zero
    private var icon: NSImage
    private var folderTile: NSView?
    private let artworkLayer = CALayer()
    private let artworkHost = NSView()
    /// Widget and folder tiles use the same continuous corner as app icons.
    private let background = NSView()
    private let canvas = DockItemCanvas()
    var animatesArtwork = false
    var animationView: NSView { item.kind == .widget || item.kind == .spacer ? self : artworkHost }
    private let folderPreview = NSImageView()
    private var grouping = false { didSet { canvas.needsDisplay = true } }
    private(set) var isLaunching = false
    var cornerRadius: CGFloat { (iconSize * 0.2237).rounded() }

    init(item: DockItem, iconSize: CGFloat, vertical: Bool) {
        self.item = item
        self.iconSize = iconSize
        self.vertical = vertical
        self.icon = NativeApplications.icon(for: item)
        self.runningCount = NativeApplications.runningCount(item)
        super.init(frame: .zero)
        toolTip = item.title
        wantsLayer = true
        clipsToBounds = false
        background.wantsLayer = true
        background.layer?.cornerCurve = .continuous
        addSubview(background)
        artworkHost.wantsLayer = true
        artworkHost.layerContentsRedrawPolicy = .onSetNeedsDisplay
        artworkHost.clipsToBounds = false
        addSubview(artworkHost)
        // The compositor scales this layer during magnification. Rasterizing at
        // the largest magnified size keeps icons sharp instead of upscaling the
        // resting bitmap; trilinear filtering keeps the resting size smooth.
        artworkLayer.contentsGravity = .resizeAspect
        artworkLayer.minificationFilter = .trilinear
        artworkLayer.magnificationFilter = .linear
        artworkHost.layer?.addSublayer(artworkLayer)
        canvas.owner = self
        addSubview(canvas)
        updateArtwork()
        updateBackground()
        refreshIfNeeded(at: Date())
        setAccessibilityElement(item.kind != .spacer)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.title)
        setAccessibilityHelp(item.kind == .widget ? "Click to edit. Drag to reorder." : "Click to open. Drag to reorder.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func resolved(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    private func updateBackground() {
        guard let layer = background.layer else { return }
        background.isHidden = item.kind != .widget
        layer.cornerRadius = cornerRadius
        if item.widget == .note {
            layer.backgroundColor = NSColor(calibratedRed: 0.98, green: 0.85, blue: 0.34, alpha: 0.9).cgColor
            layer.borderWidth = 0
        } else {
            layer.backgroundColor = resolved(.labelColor.withAlphaComponent(0.07))
            layer.borderColor = resolved(.labelColor.withAlphaComponent(0.09))
            layer.borderWidth = 1
        }
        if let tile = folderTile?.layer {
            tile.backgroundColor = resolved(.labelColor.withAlphaComponent(0.1))
            tile.borderColor = resolved(.labelColor.withAlphaComponent(0.14))
        }
    }

    private func updateArtwork() {
        artworkLayer.isHidden = [.folder, .widget, .spacer].contains(item.kind)
        if !artworkLayer.isHidden { rasterizeIcon() }
        if item.kind == .folder {
            if folderTile == nil {
                folderPreview.imageScaling = .scaleProportionallyUpOrDown
                // A flat tile instead of glass on glass: nested materials blend
                // into the shelf and Liquid Glass advises against stacking them.
                let tile = NSView()
                tile.wantsLayer = true
                tile.layer?.cornerCurve = .continuous
                tile.layer?.cornerRadius = cornerRadius
                tile.layer?.borderWidth = 1
                tile.addSubview(folderPreview)
                artworkHost.addSubview(tile)
                folderTile = tile
            }
            folderPreview.image = icon
        } else {
            folderTile?.removeFromSuperview()
            folderTile = nil
        }
        needsLayout = true
    }

    private func rasterizeIcon() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        artworkLayer.contentsScale = scale
        artworkLayer.contents = NativeIconRaster.cgImage(icon, side: iconSize * (1 + NativeDockWave.maximumGrowth), scale: scale)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if !artworkLayer.isHidden { rasterizeIcon() }
    }

    func resetArtwork() {
        animatesArtwork = false
        animationView.layer?.removeAllAnimations()
        animationView.layer?.transform = CATransform3DIdentity
        animationView.alphaValue = 1
        needsLayout = true
        layoutSubtreeIfNeeded()
        if isLaunching { addLaunchBounce() }
    }

    func refreshRunningIndicator() {
        let value = NativeApplications.runningCount(item)
        guard value != runningCount else { return }
        runningCount = value
        canvas.needsDisplay = true
    }

    override func layout() {
        super.layout()
        background.frame = bounds.insetBy(dx: 1, dy: 1)
        canvas.frame = bounds
        guard !animatesArtwork else { return }
        let side = min(iconSize, bounds.width - 2, bounds.height - 5)
        let rect = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - 5 - side) / 2, width: side, height: side)
        artworkHost.frame = rect
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artworkLayer.frame = artworkHost.bounds
        CATransaction.commit()
        folderTile?.frame = artworkHost.bounds
        folderPreview.frame = artworkHost.bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    private func text(_ string: String, at rect: NSRect, size: CGFloat = 12, weight: NSFont.Weight = .regular, color: NSColor = .labelColor, mono: Bool = false) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        (string as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    fileprivate func drawContent() {
        if item.kind == .spacer {
            NSColor.separatorColor.setFill()
            let line = vertical ? NSRect(x: 12, y: bounds.midY, width: bounds.width - 24, height: 1) : NSRect(x: bounds.midX, y: 10, width: 1, height: bounds.height - 20)
            line.fill()
            return
        }
        if grouping {
            NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }
        if item.kind == .widget {
            drawWidget()
        } else if runningCount > 0 {
            let spacing = min(6, max(1, bounds.width - 12) / CGFloat(runningCount))
            let diameter = min(3.5, spacing / 2)
            let width = CGFloat(runningCount - 1) * spacing + diameter
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 1.5
            shadow.shadowOffset = NSSize(width: 0, height: -0.5)
            shadow.set()
            NSColor.labelColor.withAlphaComponent(0.75).setFill()
            for index in 0..<runningCount {
                NSBezierPath(ovalIn: NSRect(x: bounds.midX - width / 2 + CGFloat(index) * spacing,
                    y: bounds.maxY - 3.5, width: diameter, height: diameter)).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawWidget() {
        guard let kind = item.widget else { return }
        let item = controller?.profile?.items.first(where: { $0.id == self.item.id }) ?? self.item
        let y = (bounds.height - 34) / 2
        if kind == .focus {
            let radius: CGFloat = vertical ? 11 : 13
            let center = NSPoint(x: vertical ? bounds.midX : 22, y: vertical ? 18 : bounds.midY)
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setStroke(); ring.lineWidth = 3; ring.stroke()
            let progress = min(1, item.timerValue() / item.duration)
            let arc = NSBezierPath(); arc.lineWidth = 3; arc.lineCapStyle = .round
            arc.appendArc(withCenter: center, radius: radius, startAngle: -90, endAngle: -90 + 360 * progress, clockwise: false)
            NSColor.systemOrange.setStroke(); arc.stroke()
            let value = timeString(item.timerValue())
            text(value, at: NSRect(x: vertical ? 8 : 44, y: vertical ? 35 : y, width: bounds.width - (vertical ? 12 : 47), height: 20), size: 16, weight: .medium, mono: true)
            text(item.startedAt == nil ? "Focus" : item.timerValue() == 0 ? "Complete" : "Focusing", at: NSRect(x: vertical ? 8 : 44, y: vertical ? 56 : y + 21, width: 75, height: 14), size: 10, color: .secondaryLabelColor)
            setAccessibilityValue("\(value), focus timer")
            return
        }
        if kind == .calendar {
            text(Date().formatted(.dateTime.weekday(.abbreviated)).uppercased(), at: NSRect(x: 10, y: y, width: 30, height: 12), size: 8, weight: .bold, color: .systemRed)
            text(Date().formatted(.dateTime.day()), at: NSRect(x: 10, y: y + 11, width: 30, height: 28), size: 24, weight: .regular, mono: true)
            if !vertical {
                text(Date().formatted(.dateTime.month(.wide)), at: NSRect(x: 45, y: y + 2, width: 75, height: 16), size: 11, weight: .medium)
                text("Calendar", at: NSRect(x: 45, y: y + 21, width: 75, height: 14), size: 10, color: .secondaryLabelColor)
            }
            return
        }
        if kind == .note {
            setAccessibilityValue(item.note)
            text(item.note, at: bounds.insetBy(dx: 10, dy: 8), size: 11, weight: .medium, color: .black)
            return
        }
        let value: String
        let caption: String
        switch kind {
        case .clock: value = Date().formatted(date: .omitted, time: .shortened); caption = "Local time"
        case .worldClock:
            let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: item.timeZone); formatter.dateFormat = "HH:mm"
            value = formatter.string(from: Date()); caption = item.timeZone.split(separator: "/").last?.replacingOccurrences(of: "_", with: " ") ?? "World clock"
        case .hydration: value = "\(item.dailyCount) / 8"; caption = vertical ? "Glasses" : "Glasses today"
        case .reminders: value = "\(item.checklist.filter { !$0.done }.count) tasks"; caption = item.checklist.first(where: { !$0.done })?.text ?? "Checklist"
        case .stopwatch: value = timeString(item.timerValue()); caption = "Stopwatch"
        case .countdown:
            let seconds = max(0, (item.deadline ?? Date()).timeIntervalSinceNow)
            value = seconds > 86400 ? "\(Int(seconds / 86400)) days" : timeString(seconds)
            caption = item.title
        case .battery: value = NativeBattery.percentage.map { "\($0)%" } ?? "—"; caption = "Battery"
        case .cpu, .memory, .webValue:
            let reading = dataReading
            value = reading.value
            caption = reading.isError ? "Update failed" : item.title
            toolTip = item.title + "\n" + reading.detail
        case .custom:
            let reading = customReading
            value = reading.output.value
            caption = reading.isError ? "Update failed" : reading.output.detail.isEmpty ? item.title : reading.output.detail
            toolTip = item.title + "\n" + reading.status
        default: value = ""; caption = kind.title
        }
        let x: CGFloat = vertical ? 7 : 12
        text(value, at: NSRect(x: x, y: y, width: bounds.width - x * 2, height: 22), size: vertical ? 15 : 17, weight: .medium, mono: kind != .custom)
        text(caption, at: NSRect(x: x, y: y + 23, width: bounds.width - x * 2, height: 14), size: 10, color: .secondaryLabelColor)
        setAccessibilityValue("\(value), \(caption)")
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let value = Int(min(315_360_000, max(0, seconds)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    func refreshIfNeeded(at date: Date) {
        guard let kind = item.widget else { return }
        let interval: TimeInterval
        switch kind {
        case .cpu, .memory, .webValue, .countdown, .custom: interval = 1
        case .focus, .stopwatch: guard item.startedAt != nil else { return }; interval = 1
        case .clock, .worldClock, .battery: interval = 60
        case .calendar, .hydration: interval = 60
        default: return
        }
        let bucket = Int(date.timeIntervalSince1970 / interval)
        guard bucket != lastRefreshBucket else { return }
        lastRefreshBucket = bucket
        if [.cpu, .memory, .webValue].contains(kind) {
            let reading = NativeWidgetData.shared.reading(for: item)
            guard reading != dataReading else { return }
            dataReading = reading
        } else if kind == .custom {
            let reading = NativeCustomWidgetData.shared.reading(for: item)
            guard reading != customReading else { return }
            customReading = reading
        }
        canvas.needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
        canvas.needsDisplay = true
    }

    // MARK: Press and launch feedback

    private func setPressed(_ pressed: Bool) {
        pressAmount = pressed ? 1 : 0
        guard let layer, !NativeMotion.reducesMotion else { return }
        let scale: CGFloat = item.kind == .widget ? 1 - 0.015 * pressAmount : 1 - 0.06 * pressAmount
        let transform = CATransform3DMakeScale(scale, scale, 1)
        let previous = layer.presentation()?.transform ?? layer.transform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        let animation = NativeMotion.spring("transform", duration: pressed ? 0.1 : 0.3, bounce: pressed ? 0 : 0.3)
        animation.fromValue = NSValue(caTransform3D: previous)
        animation.toValue = NSValue(caTransform3D: transform)
        layer.add(animation, forKey: "dockInteraction")
        CATransaction.commit()
    }

    /// Bounces the artwork until `endLaunchBounce`, like the system Dock while
    /// an application is starting. Away from the screen edge on side docks.
    func beginLaunchBounce() {
        guard !isLaunching, !NativeMotion.reducesMotion else { return }
        isLaunching = true
        addLaunchBounce()
    }

    func endLaunchBounce() {
        guard isLaunching else { return }
        isLaunching = false
        animationView.layer?.removeAnimation(forKey: "dockLaunchBounce")
    }

    private func addLaunchBounce() {
        guard let layer = animationView.layer else { return }
        let edge = controller?.profile?.appearance.position ?? "Bottom"
        // The magnified dock has room above the shelf. A resting dock window
        // is only as large as the shelf, so bounce within its margin there.
        var distance = iconSize * 0.6
        if let window, let content = window.contentView {
            let artwork = animationView.convert(animationView.bounds, to: nil)
            let room: CGFloat
            switch edge {
            case "Left": room = content.bounds.maxX - artwork.maxX
            case "Right": room = artwork.minX - content.bounds.minX
            default: room = content.bounds.maxY - artwork.maxY
            }
            distance = min(distance, max(4, room - 2))
        }
        let bounce = CAKeyframeAnimation(keyPath: edge == "Left" ? "transform.translation.x" : edge == "Right" ? "transform.translation.x" : "transform.translation.y")
        let peak: CGFloat = edge == "Left" ? distance : -distance
        bounce.values = [0, peak, 0, 0]
        bounce.keyTimes = [0, 0.38, 0.76, 1]
        bounce.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .linear)]
        bounce.duration = 0.8
        bounce.repeatCount = .infinity
        bounce.isAdditive = true
        layer.add(bounce, forKey: "dockLaunchBounce")
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragging = false
        setPressed(true)
    }
    override func mouseUp(with event: NSEvent) {
        setPressed(false)
        if dragging { controller?.finishDrag(at: event.locationInWindow) }
        else if bounds.contains(convert(event.locationInWindow, from: nil)) { controller?.open(item) }
        dragging = false
    }
    override func accessibilityPerformPress() -> Bool { controller?.open(item); return true }
    override func menu(for event: NSEvent) -> NSMenu? { controller?.menu(for: item) }

    func showGrouping(_ value: Bool) { grouping = value }

    override func mouseDragged(with event: NSEvent) {
        guard let controller else { return }
        let point = convert(event.locationInWindow, from: nil)
        if !dragging {
            guard hypot(point.x - dragStart.x, point.y - dragStart.y) > 4,
                  (item.kind == .application || controller.profile?.items.contains(where: { $0.id == item.id }) == true) else { return }
            dragging = true
            setPressed(false)
            controller.beginDrag(self)
        }
        controller.updateDrag(at: event.locationInWindow)
    }
}

/// Draws running dots and widget text above the artwork and tile background,
/// so backgrounds can be Core Animation layers with continuous corners.
private final class DockItemCanvas: FlippedNativeView {
    weak var owner: NativeDockItemView?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { owner?.drawContent() }
}

enum NativeIconRaster {
    /// Renders an icon at `side` points for the given backing scale, choosing
    /// the best representation for that size rather than the resting one.
    static func cgImage(_ image: NSImage, side: CGFloat, scale: CGFloat) -> CGImage? {
        let pixels = max(1, Int((side * scale).rounded(.up)))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .sourceOver, fraction: 1)
        return rep.cgImage
    }
}

enum NativeBattery {
    static var percentage: Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let data = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = data[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = data[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return Int(Double(current) / Double(maximum) * 100)
        }
        return nil
    }
}
#endif
