#if os(macOS)
import AppKit
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
    /// Read only by battery widgets, in `refreshIfNeeded`.
    private var battery: NativeBattery.Status?
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
    private let folderPreview = CALayer()
    private var grouping = false { didSet { if grouping != oldValue { canvas.needsDisplay = true } } }
    private(set) var isLaunching = false
    var cornerRadius: CGFloat { NativeDockStyle.tileRadius(iconSize: iconSize) }
    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    /// Previews of docks that are not on screen show widgets without fetching
    /// web values or running custom scripts and commands for them.
    private let live: Bool

    init(item: DockItem, iconSize: CGFloat, vertical: Bool, live: Bool = true) {
        self.live = live
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
        for layer in [artworkLayer, folderPreview] {
            layer.contentsGravity = .resizeAspect
            layer.minificationFilter = .trilinear
            layer.magnificationFilter = .linear
        }
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

    private var hairline: CGFloat { 1 / (window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2) }

    private func updateBackground() {
        guard let layer = background.layer else { return }
        background.isHidden = item.kind != .widget
        layer.cornerRadius = cornerRadius
        let dark = isDark
        layer.backgroundColor = (item.widget == .note ? NativeDockStyle.noteFill(dark: dark) : NativeDockStyle.tileFill(dark: dark)).cgColor
        layer.borderColor = NativeDockStyle.tileRim(dark: dark).cgColor
        layer.borderWidth = hairline
        if let tile = folderTile?.layer {
            tile.backgroundColor = NativeDockStyle.tileFill(dark: dark).cgColor
            tile.borderColor = NativeDockStyle.tileRim(dark: dark).cgColor
            tile.borderWidth = hairline
        }
    }

    private func updateArtwork() {
        artworkLayer.isHidden = [.folder, .widget, .spacer].contains(item.kind)
        if !artworkLayer.isHidden { rasterizeIcon() }
        if item.kind == .folder {
            if folderTile == nil {
                // A flat tile instead of glass on glass: nested materials blend
                // into the shelf and Liquid Glass advises against stacking them.
                let tile = NSView()
                tile.wantsLayer = true
                tile.layer?.cornerCurve = .continuous
                tile.layer?.cornerRadius = cornerRadius
                tile.layer?.addSublayer(folderPreview)
                artworkHost.addSubview(tile)
                folderTile = tile
                updateBackground()
            }
            rasterizeIcon()
        } else {
            folderTile?.removeFromSuperview()
            folderTile = nil
        }
        needsLayout = true
    }

    /// The folder's rasterized preview, which changes when its apps change.
    var folderArtwork: AnyObject? { folderPreview.contents as AnyObject? }

    private func rasterizeIcon() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let side = iconSize * (1 + NativeDockWave.maximumGrowth)
        let target = item.kind == .folder ? folderPreview : artworkLayer
        target.contentsScale = scale
        // Folder previews draw adaptive colours, such as the "+N" badge, so
        // render them in the dock's appearance rather than the app's.
        var image: CGImage?
        effectiveAppearance.performAsCurrentDrawingAppearance { image = NativeIconRaster.cgImage(icon, side: side, scale: scale) }
        target.contents = image
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if !artworkLayer.isHidden || item.kind == .folder { rasterizeIcon() }
        updateBackground()
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
        folderPreview.frame = artworkHost.bounds
        CATransaction.commit()
        folderTile?.frame = artworkHost.bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    /// The tile as it looks now, for dragging. Drawn directly rather than
    /// from the view's cache, which leaves out layer-hosted icons.
    func snapshot() -> NSImage {
        let size = bounds.size
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard size.width > 0, size.height > 0,
              let context = CGContext(data: nil, width: Int((size.width * scale).rounded(.up)), height: Int((size.height * scale).rounded(.up)),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return NSImage(size: size) }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = isDark
            let artwork = artworkHost.frame
            func tile(_ rect: NSRect, fill: NSColor) {
                let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
                fill.setFill(); path.fill()
                NativeDockStyle.tileRim(dark: dark).setStroke(); path.lineWidth = hairline; path.stroke()
            }
            if item.kind == .widget {
                tile(bounds.insetBy(dx: 1, dy: 1), fill: item.widget == .note ? NativeDockStyle.noteFill(dark: dark) : NativeDockStyle.tileFill(dark: dark))
            } else if item.kind != .spacer {
                if item.kind == .folder { tile(artwork, fill: NativeDockStyle.tileFill(dark: dark)) }
                icon.draw(in: artwork, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            }
            drawContent()
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return NSImage(size: size) }
        return NSImage(cgImage: image, size: size)
    }

    // MARK: Drawing

    private func text(_ string: String, in rect: NSRect, font: NSFont, color: NSColor = .labelColor,
                      alignment: NSTextAlignment = .left, lines: Int = 1) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        if lines == 1 {
            (string as NSString).draw(in: rect, withAttributes: attributes)
        } else {
            (string as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes, context: nil)
        }
    }

    /// Shrinks a value's font until it fits, so long values stay whole.
    private func fitted(_ string: String, _ font: NSFont, width: CGFloat, minimum: CGFloat = 10) -> NSFont {
        var font = font
        while (string as NSString).size(withAttributes: [.font: font]).width > width, font.pointSize > minimum {
            font = NSFont(descriptor: font.fontDescriptor, size: font.pointSize - 0.5) ?? font
        }
        return font
    }

    private func symbol(_ name: String, in rect: NSRect, size: CGFloat, color: NSColor, weight: NSFont.Weight = .semibold) {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        // Wide symbols, such as batteries, shrink to stay inside their box.
        let natural = image.size
        let scale = min(1, rect.width / max(1, natural.width), rect.height / max(1, natural.height))
        let fitted = NSSize(width: natural.width * scale, height: natural.height * scale)
        let origin = NSPoint(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2)
        image.draw(in: NSRect(origin: origin, size: fitted), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func bar(_ fraction: Double, in rect: NSRect, color: NSColor) {
        let radius = rect.height / 2
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        let width = max(rect.height, rect.width * CGFloat(min(1, max(0, fraction))))
        guard fraction > 0 else { return }
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: width, height: rect.height), xRadius: radius, yRadius: radius).fill()
    }

    private func ring(center: NSPoint, radius: CGFloat, width: CGFloat, fraction: Double, color: NSColor) {
        let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        track.lineWidth = width
        NSColor.labelColor.withAlphaComponent(0.12).setStroke(); track.stroke()
        guard fraction > 0 else { return }
        // Flipped view: clockwise in view coordinates reads clockwise on screen.
        let arc = NSBezierPath()
        arc.lineWidth = width; arc.lineCapStyle = .round
        arc.appendArc(withCenter: center, radius: radius, startAngle: -90, endAngle: -90 + 360 * CGFloat(min(1, fraction)), clockwise: false)
        color.setStroke(); arc.stroke()
    }

    fileprivate func drawContent() {
        if item.kind == .spacer {
            NSColor.labelColor.withAlphaComponent(0.18).setFill()
            let line = vertical ? NSRect(x: 14, y: bounds.midY - 0.5, width: bounds.width - 28, height: 1)
                : NSRect(x: bounds.midX - 0.5, y: 12, width: 1, height: bounds.height - 24)
            NSBezierPath(roundedRect: line, xRadius: 0.5, yRadius: 0.5).fill()
            return
        }
        if grouping {
            NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }
        if item.kind == .widget {
            drawWidget()
        } else if runningCount > 0 {
            NativeDockItemView.drawRunningDots(count: runningCount, centerX: bounds.midX, y: bounds.maxY - 3.5, width: bounds.width)
        }
    }

    /// The same indicator in the dock and in folders.
    static func drawRunningDots(count: Int, centerX: CGFloat, y: CGFloat, width: CGFloat) {
        let spacing = min(6, max(1, width - 12) / CGFloat(count))
        let diameter = min(3.5, max(2, spacing - 2))
        let total = CGFloat(count - 1) * spacing + diameter
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        NSColor.labelColor.withAlphaComponent(0.75).setFill()
        for index in 0..<count {
            NSBezierPath(ovalIn: NSRect(x: centerX - total / 2 + CGFloat(index) * spacing, y: y, width: diameter, height: diameter)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// What a widget shows: a heading with its glyph, a value, and either a
    /// detail line or a progress bar.
    private struct Face {
        var glyph: String
        var heading: String
        var value: String
        var detail = ""
        var progress: Double?
        var color: NSColor
        var ring = false
        var icon: NSImage?
        var centerSymbol: String?
    }

    private func face(for kind: WidgetKind, item: DockItem) -> Face {
        let now = Date()
        switch kind {
        case .clock:
            return Face(glyph: kind.symbol, heading: item.title, value: now.formatted(date: .omitted, time: .shortened),
                        detail: now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), color: kind.accent)
        case .worldClock:
            let zone = TimeZone(identifier: item.timeZone) ?? .current
            let hours = Double(zone.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)) / 3600
            let offset = hours == 0 ? "Same time" : (hours > 0 ? "+" : "−") + abs(hours).formatted(.number.precision(.fractionLength(0...1))) + " h"
            return Face(glyph: kind.symbol, heading: NativeWidgetFormat.city(item.timeZone), value: NativeWidgetFormat.time(in: item.timeZone, at: now),
                        detail: offset, color: kind.accent)
        case .hydration:
            return Face(glyph: "drop.fill", heading: item.title, value: "\(item.dailyCount) / 8", progress: Double(item.dailyCount) / 8, color: kind.accent)
        case .reminders:
            let open = item.checklist.filter { !$0.done }
            return Face(glyph: kind.symbol, heading: item.title, value: NativeWidgetFormat.tasks(open: open.count, total: item.checklist.count),
                        detail: open.first?.text ?? (item.checklist.isEmpty ? "Add a task" : "Nice work"), color: kind.accent)
        case .stopwatch:
            return Face(glyph: kind.symbol, heading: item.title, value: NativeWidgetFormat.clock(item.timerValue()),
                        detail: item.startedAt != nil ? "Running" : item.remaining > 0 ? "Paused" : "Ready", color: kind.accent)
        case .countdown:
            let deadline = item.deadline ?? now
            return Face(glyph: kind.symbol, heading: item.title, value: NativeWidgetFormat.countdown(deadline.timeIntervalSince(now)),
                        detail: deadline <= now ? "Done" : deadline.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), color: kind.accent)
        case .battery:
            let color = NativeBattery.color(for: battery)
            return Face(glyph: NativeBattery.symbol(for: battery), heading: battery?.charging == true ? "Charging" : item.title,
                        value: battery.map { "\($0.percentage)%" } ?? "—", detail: battery == nil ? "No battery" : "",
                        progress: battery.map { Double($0.percentage) / 100 }, color: color)
        case .cpu, .memory, .webValue:
            let reading = dataReading
            toolTip = item.title + "\n" + reading.detail
            let fraction = kind == .webValue ? nil : NativeWidgetFormat.fraction(from: reading.value)
            return Face(glyph: kind.symbol, heading: item.title, value: reading.value,
                        detail: reading.isError ? "Update failed" : fraction == nil ? reading.detail : "", progress: reading.isError ? nil : fraction, color: kind.accent)
        case .custom:
            let reading = customReading
            toolTip = item.title + "\n" + reading.status
            let output = reading.output
            let progress = reading.isError ? nil : output.progress
            let symbol = output.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil ? nil : $0 }
            return Face(glyph: symbol ?? (item.symbol.isEmpty ? kind.symbol : item.symbol), heading: item.title, value: output.value,
                        detail: reading.isError ? "Update failed" : output.detail, progress: progress,
                        color: NativeWidgetPresentation.color(output.tint, progress: progress, fallback: kind.accent),
                        ring: output.style == "ring" && progress != nil, icon: NativeWidgetPresentation.appIcon(output.apps), centerSymbol: symbol)
        default:
            return Face(glyph: kind.symbol, heading: kind.title, value: "", color: kind.accent)
        }
    }

    private func drawWidget() {
        guard let kind = item.widget else { return }
        let item = controller?.profile?.items.first(where: { $0.id == self.item.id }) ?? self.item
        switch kind {
        case .focus: drawFocus(item)
        case .calendar: drawCalendar()
        case .note:
            setAccessibilityValue(item.note)
            let dark = isDark
            let inset = bounds.insetBy(dx: vertical ? 8 : 11, dy: 9)
            text(item.note.isEmpty ? "Write a note…" : item.note, in: inset, font: .systemFont(ofSize: 11.5, weight: .medium),
                 color: NativeDockStyle.noteText(dark: dark).withAlphaComponent(item.note.isEmpty ? 0.55 : 1), lines: 5)
        default:
            let face = face(for: kind, item: item)
            vertical ? drawVertical(face) : drawHorizontal(face)
            setAccessibilityValue([face.value, face.heading, face.detail].filter { !$0.isEmpty }.joined(separator: ", "))
        }
    }

    /// A progress ring with the widget's app icon or symbol inside, like an
    /// activity ring; the value and its detail sit beside it.
    private func drawRing(_ face: Face) {
        let progress = face.progress ?? 0
        func center(_ point: NSPoint, radius: CGFloat) {
            if let icon = face.icon {
                let side = (radius * 1.3).rounded()
                icon.draw(in: NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side), from: .zero,
                          operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            } else if let name = face.centerSymbol {
                symbol(name, in: NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2), size: radius * 0.78, color: face.color)
            } else {
                let percent = "\(Int((progress * 100).rounded()))"
                let font = NativeDockStyle.valueFont(radius * 0.62)
                text(percent, in: NSRect(x: point.x - radius, y: point.y - font.pointSize * 0.62, width: radius * 2, height: font.pointSize * 1.3), font: font, alignment: .center)
            }
        }
        if vertical {
            let radius: CGFloat = 15
            let point = NSPoint(x: bounds.midX, y: 25)
            ring(center: point, radius: radius, width: 3.5, fraction: progress, color: face.color)
            center(point, radius: radius)
            let valueFont = fitted(face.value, NativeDockStyle.valueFont(13), width: bounds.width - 10)
            text(face.value, in: NSRect(x: 5, y: 47 + (13 - valueFont.pointSize) / 2, width: bounds.width - 10, height: 18), font: valueFont, alignment: .center)
            return
        }
        let compact = bounds.height < 60
        let radius: CGFloat = compact ? 15 : 19
        let point = NSPoint(x: 11 + radius, y: bounds.midY)
        ring(center: point, radius: radius, width: compact ? 3.5 : 4, fraction: progress, color: face.color)
        center(point, radius: radius)
        let x = point.x + radius + 10
        let width = bounds.width - x - 8
        let valueFont = fitted(face.value, NativeDockStyle.valueFont(compact ? 15 : 17), width: width)
        let valueHeight = ceil(valueFont.ascender - valueFont.descender) + 1
        let detailFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let lines = Self.detailLines(face.detail, width: width, font: detailFont, maximum: compact ? 1 : 2)
        var y = ((bounds.height - valueHeight - CGFloat(lines.count) * 13) / 2).rounded()
        text(face.value, in: NSRect(x: x, y: y, width: width, height: valueHeight), font: valueFont)
        y += valueHeight
        for line in lines {
            text(line, in: NSRect(x: x, y: y, width: width, height: 13), font: detailFont, color: .secondaryLabelColor)
            y += 13
        }
    }

    /// Splits a detail such as "Codex · Weekly · 6d" between its parts, so a
    /// second line never starts with a separator or a broken phrase.
    static func detailLines(_ detail: String, width: CGFloat, font: NSFont, maximum: Int) -> [String] {
        guard !detail.isEmpty, maximum > 0 else { return [] }
        func fits(_ text: String) -> Bool { (text as NSString).size(withAttributes: [.font: font]).width <= width }
        let parts = detail.components(separatedBy: " · ")
        var lines: [String] = []
        var current = ""
        for part in parts {
            let joined = current.isEmpty ? part : current + " · " + part
            if fits(joined) || current.isEmpty { current = joined; continue }
            lines.append(current)
            current = part
        }
        lines.append(current)
        guard lines.count > maximum else { return lines }
        // Whatever does not fit joins the last line, which truncates.
        return Array(lines.prefix(maximum - 1)) + [lines.dropFirst(maximum - 1).joined(separator: " · ")]
    }

    private func drawHorizontal(_ face: Face) {
        if face.ring { drawRing(face); return }
        let x: CGFloat = 11
        let width = bounds.width - x * 2
        let compact = bounds.height < 60
        // A bar and a detail line both need the room the heading would take.
        let showHeading = bounds.height >= 50 && (face.progress == nil || face.detail.isEmpty)
        let valueFont = NativeDockStyle.valueFont(compact ? 16 : 19)
        let valueHeight = ceil(valueFont.ascender - valueFont.descender) + 1
        let footerHeight: CGFloat = (face.progress != nil ? 4 : 0) + (face.detail.isEmpty ? 0 : face.progress != nil ? 17 : 13)
        let headingHeight: CGFloat = showHeading ? 13 : 0
        let total = headingHeight + (showHeading ? 2 : 0) + valueHeight + (footerHeight > 0 ? (face.progress != nil ? 5 : 1) + footerHeight : 0)
        var y = ((bounds.height - total) / 2).rounded()
        if showHeading {
            symbol(face.glyph, in: NSRect(x: x, y: y, width: 13, height: 13), size: 10, color: face.color)
            text(face.heading, in: NSRect(x: x + 17, y: y - 0.5, width: width - 17, height: 14), font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor)
            y += headingHeight + 2
        }
        text(face.value, in: NSRect(x: x, y: y, width: width, height: valueHeight), font: fitted(face.value, valueFont, width: width))
        y += valueHeight
        if let progress = face.progress {
            bar(progress, in: NSRect(x: x, y: y + 5, width: width, height: 4), color: face.color)
            if !face.detail.isEmpty {
                text(face.detail, in: NSRect(x: x, y: y + 12, width: width, height: 13), font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
            }
        } else if !face.detail.isEmpty {
            text(face.detail, in: NSRect(x: x, y: y + 1, width: width, height: 13), font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
        }
    }

    private func drawVertical(_ face: Face) {
        if face.ring { drawRing(face); return }
        let width = bounds.width - 12
        symbol(face.glyph, in: NSRect(x: 6, y: 9, width: width, height: 16), size: 13, color: face.color)
        let valueFont = fitted(face.value, NativeDockStyle.valueFont(14), width: width)
        text(face.value, in: NSRect(x: 6, y: 28 + (14 - valueFont.pointSize) / 2, width: width, height: 19), font: valueFont, alignment: .center)
        if let progress = face.progress {
            bar(progress, in: NSRect(x: 12, y: 54, width: bounds.width - 24, height: 4), color: face.color)
        } else {
            let caption = face.detail.isEmpty ? face.heading : face.detail
            text(caption, in: NSRect(x: 5, y: 50, width: bounds.width - 10, height: 13), font: .systemFont(ofSize: 9.5, weight: .medium), color: .secondaryLabelColor, alignment: .center)
        }
    }

    private func drawFocus(_ item: DockItem) {
        let remaining = item.timerValue()
        let progress = item.duration > 0 ? remaining / item.duration : 0
        let value = NativeWidgetFormat.clock(remaining)
        let status = item.startedAt == nil ? (remaining <= 0 ? "Complete" : remaining < item.duration ? "Paused" : "Focus") : remaining == 0 ? "Complete" : "Focusing"
        let color = WidgetKind.focus.accent
        if vertical {
            let center = NSPoint(x: bounds.midX, y: 22)
            ring(center: center, radius: 12, width: 3, fraction: progress, color: color)
            symbol(item.startedAt == nil ? "play.fill" : "pause.fill", in: NSRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12), size: 8, color: color)
            text(value, in: NSRect(x: 4, y: 40, width: bounds.width - 8, height: 18), font: fitted(value, NativeDockStyle.valueFont(13), width: bounds.width - 8), alignment: .center)
            text(status, in: NSRect(x: 4, y: 57, width: bounds.width - 8, height: 12), font: .systemFont(ofSize: 9.5, weight: .medium), color: .secondaryLabelColor, alignment: .center)
        } else {
            let compact = bounds.height < 60
            let radius: CGFloat = compact ? 13 : 16
            let center = NSPoint(x: 11 + radius, y: bounds.midY)
            ring(center: center, radius: radius, width: compact ? 3 : 3.5, fraction: progress, color: color)
            symbol(item.startedAt == nil ? "play.fill" : "pause.fill", in: NSRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14), size: compact ? 8 : 10, color: color)
            let x = center.x + radius + 9
            let valueFont = NativeDockStyle.valueFont(compact ? 15 : 17)
            let valueHeight = ceil(valueFont.ascender - valueFont.descender) + 1
            let top = ((bounds.height - valueHeight - 14) / 2).rounded()
            text(status, in: NSRect(x: x, y: top, width: bounds.width - x - 8, height: 14), font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor)
            text(value, in: NSRect(x: x, y: top + 14, width: bounds.width - x - 6, height: valueHeight), font: fitted(value, valueFont, width: bounds.width - x - 6))
        }
        setAccessibilityValue("\(value), \(status)")
    }

    private func drawCalendar() {
        let now = Date()
        let weekday = now.formatted(.dateTime.weekday(.abbreviated)).uppercased()
        let day = now.formatted(.dateTime.day())
        let red = WidgetKind.calendar.accent
        if vertical {
            text(weekday, in: NSRect(x: 4, y: 11, width: bounds.width - 8, height: 13), font: .systemFont(ofSize: 10, weight: .bold), color: red, alignment: .center)
            text(day, in: NSRect(x: 4, y: 23, width: bounds.width - 8, height: 30), font: NativeDockStyle.valueFont(24, weight: .medium), alignment: .center)
            text(now.formatted(.dateTime.month(.abbreviated)), in: NSRect(x: 4, y: 53, width: bounds.width - 8, height: 13), font: .systemFont(ofSize: 9.5, weight: .medium), color: .secondaryLabelColor, alignment: .center)
        } else {
            let compact = bounds.height < 60
            let column: CGFloat = compact ? 38 : 44
            let dayFont = NativeDockStyle.valueFont(compact ? 22 : 27, weight: .medium)
            let dayHeight = ceil(dayFont.ascender - dayFont.descender)
            let top = ((bounds.height - dayHeight - 12) / 2).rounded()
            text(weekday, in: NSRect(x: 9, y: top, width: column, height: 13), font: .systemFont(ofSize: 10, weight: .bold), color: red, alignment: .center)
            text(day, in: NSRect(x: 9, y: top + 11, width: column, height: dayHeight), font: dayFont, alignment: .center)
            let x = 9 + column + 8
            NSColor.labelColor.withAlphaComponent(0.1).setFill()
            NSRect(x: x - 5, y: top + 3, width: 1, height: dayHeight + 6).fill()
            let middle = bounds.midY
            let monthFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
            let wide = now.formatted(.dateTime.month(.wide))
            let month = (wide as NSString).size(withAttributes: [.font: monthFont]).width <= bounds.width - x - 6 ? wide : now.formatted(.dateTime.month(.abbreviated))
            text(month, in: NSRect(x: x, y: middle - 15, width: bounds.width - x - 6, height: 16), font: monthFont)
            text(now.formatted(.dateTime.year()), in: NSRect(x: x, y: middle + 1, width: bounds.width - x - 6, height: 14), font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
        }
        setAccessibilityValue(now.formatted(date: .complete, time: .omitted))
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
        if !live, [.cpu, .memory, .webValue, .custom].contains(kind) {
            // Show what the dock last displayed, or a quiet placeholder.
            if kind == .custom {
                let reading = NativeCustomWidgetData.shared.cachedReading(for: item)
                    ?? .init(output: CustomWidgetOutput(value: "—", detail: "Updates on the dock"))
                guard reading != customReading else { return }
                customReading = reading
            } else {
                let reading = NativeWidgetData.shared.cachedReading(for: item) ?? .init(value: "—", detail: "Updates on the dock")
                guard reading != dataReading else { return }
                dataReading = reading
            }
            canvas.needsDisplay = true
            return
        }
        if [.cpu, .memory, .webValue].contains(kind) {
            let reading = NativeWidgetData.shared.reading(for: item)
            guard reading != dataReading else { return }
            dataReading = reading
        } else if kind == .custom {
            let reading = NativeCustomWidgetData.shared.reading(for: item)
            guard reading != customReading else { return }
            customReading = reading
        } else if kind == .battery {
            battery = NativeBattery.status
        }
        canvas.needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if item.kind == .folder { rasterizeIcon() }
        updateBackground()
        canvas.needsDisplay = true
    }

    // MARK: Press and launch feedback

    private func setPressed(_ pressed: Bool) {
        pressAmount = pressed ? 1 : 0
        // Dimming is feedback, not motion, so it stays with Reduce Motion.
        if item.kind != .widget {
            NativeMotion.animate(pressed ? 0.1 : 0.22) { artworkHost.animator().alphaValue = pressed ? NativeDockStyle.pressAlpha : 1 }
        }
        guard let layer, !NativeMotion.reducesMotion else { return }
        let depth = 1 - (item.kind == .widget ? NativeDockStyle.widgetPressScale : NativeDockStyle.pressScale)
        let scale = 1 - depth * pressAmount
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
#endif
