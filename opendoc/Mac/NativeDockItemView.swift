#if os(macOS)
import AppKit
import IOKit.ps
import QuartzCore

final class NativeDockItemView: FlippedNativeView {
    var item: DockItem { didSet { running = NativeApplications.isRunning(item); if item.kind == .folder { icon = NativeApplications.icon(for: item) }; toolTip = item.title; setAccessibilityLabel(item.title); cachedArtwork = nil; updateFolderGlass(); lastRefreshBucket = nil; refreshIfNeeded(at: Date()); needsDisplay = true } }
    let iconSize: CGFloat
    let vertical: Bool
    weak var controller: NativeDockController?
    private var hoverAmount: CGFloat = 0
    private var pressAmount: CGFloat = 0
    private var running = false
    private var lastRefreshBucket: Int?
    private var dataReading = NativeWidgetData.Reading(value: "…", detail: "Loading…")
    private var customReading = NativeCustomWidgetData.Reading()
    private var cachedArtwork: CGImage?
    private var dropAfter: Bool? { didSet { needsDisplay = true } }
    private var dragging = false
    private var dragStart = NSPoint.zero
    private var tracking: NSTrackingArea?
    private var icon: NSImage
    private var folderGlass: NSView?
    private let folderPreview = NSImageView()
    private var grouping = false { didSet { needsDisplay = true } }

    init(item: DockItem, iconSize: CGFloat, vertical: Bool) {
        self.item = item
        self.iconSize = iconSize
        self.vertical = vertical
        self.icon = NativeApplications.icon(for: item)
        self.running = NativeApplications.isRunning(item)
        super.init(frame: .zero)
        toolTip = item.title
        wantsLayer = true
        updateFolderGlass()
        refreshIfNeeded(at: Date())
        setAccessibilityElement(item.kind != .spacer)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.title)
        setAccessibilityHelp(item.kind == .widget ? "Click to edit. Drag to reorder." : "Click to open. Drag to reorder.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        defer {
            if let dropAfter {
                NSColor.controlAccentColor.setFill()
                let marker = vertical
                    ? NSRect(x: 8, y: dropAfter ? bounds.height - 2 : 0, width: bounds.width - 16, height: 2)
                    : NSRect(x: dropAfter ? bounds.width - 2 : 0, y: 6, width: 2, height: bounds.height - 12)
                NSBezierPath(roundedRect: marker, xRadius: 1, yRadius: 1).fill()
            }
        }
        super.draw(dirtyRect)
        if item.kind == .spacer {
            NSColor.separatorColor.setFill()
            let line = vertical ? NSRect(x: 12, y: bounds.midY, width: bounds.width - 24, height: 1) : NSRect(x: bounds.midX, y: 10, width: 1, height: bounds.height - 20)
            line.fill()
            return
        }
        if grouping {
            NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12).fill()
        }
        if item.kind == .widget {
            drawWidget()
        } else {
            let side = min(iconSize, bounds.width - 2, bounds.height - 5)
            let rect = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - 5 - side) / 2, width: side, height: side)
            if item.kind != .folder {
                icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            }
            if running {
                NSColor.labelColor.withAlphaComponent(0.7).setFill()
                NSBezierPath(ovalIn: NSRect(x: bounds.midX - 1.5, y: bounds.maxY - 3, width: 3, height: 3)).fill()
            }
        }
    }

    private func updateFolderGlass() {
        if item.kind == .folder {
            if folderGlass == nil {
                folderPreview.imageScaling = .scaleProportionallyUpOrDown
                let glass = DockGlassRoot.makeFolderMaterial(containing: folderPreview)
                addSubview(glass)
                folderGlass = glass
            }
            folderPreview.image = icon
        } else {
            folderGlass?.removeFromSuperview()
            folderGlass = nil
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let side = min(iconSize, bounds.width - 2, bounds.height - 5)
        folderGlass?.frame = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - 5 - side) / 2, width: side, height: side)
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

    private func drawWidget() {
        guard let kind = item.widget else { return }
        let item = controller?.profile?.items.first(where: { $0.id == self.item.id }) ?? self.item
        let area = bounds.insetBy(dx: 1, dy: 1)
        if kind == .note {
            NSColor(calibratedRed: 0.98, green: 0.85, blue: 0.34, alpha: 0.88).setFill()
        } else { NSColor.labelColor.withAlphaComponent(0.045).setFill() }
        NSBezierPath(roundedRect: area, xRadius: 10, yRadius: 10).fill()
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
            caption = reading.output.detail.isEmpty ? item.title : reading.output.detail
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
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
        cachedArtwork = nil
        needsDisplay = true
    }

    func snapshotArtwork() -> CGImage? {
        if let cachedArtwork { return cachedArtwork }
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        let opacity = alphaValue
        CATransaction.begin(); CATransaction.setDisableActions(true)
        alphaValue = 1
        cacheDisplay(in: bounds, to: bitmap)
        alphaValue = opacity
        CATransaction.commit()
        cachedArtwork = bitmap.cgImage
        return cachedArtwork
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        cachedArtwork = nil
        needsDisplay = true
    }

    func setProximity(_ amount: CGFloat) {
        guard abs(hoverAmount - amount) > 0.025 || amount == 0 && hoverAmount != 0 else { return }
        hoverAmount = amount
        animateTransform(duration: 0.14)
    }
    private func setPressed(_ pressed: Bool) {
        pressAmount = pressed ? 1 : 0
        animateTransform(duration: pressed ? 0.08 : 0.18)
    }
    private func animateTransform(duration: TimeInterval) {
        guard let layer else { return }
        let scale: CGFloat = NativeMotion.reducesMotion ? 1 : item.kind == .widget ? 1 - 0.015 * pressAmount : 1 + 0.10 * hoverAmount - 0.05 * pressAmount
        let transform = CATransform3DMakeScale(scale, scale, 1)
        let previous = layer.presentation()?.transform ?? layer.transform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        CATransaction.commit()
        layer.removeAnimation(forKey: "dockInteraction")
        guard !NativeMotion.reducesMotion else { return }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: previous)
        animation.toValue = NSValue(caTransform3D: transform)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.3, 1)
        layer.add(animation, forKey: "dockInteraction")
    }
    override func mouseEntered(with event: NSEvent) { if controller == nil { setProximity(1) } }
    override func mouseExited(with event: NSEvent) { if controller == nil { setProximity(0) } }
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

    func showInsertion(after: Bool?) { dropAfter = after }

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
