#if os(macOS)
import AppKit
import QuartzCore

/// The magnified row uses cached artwork. Pointer movement changes layer geometry only.
final class NativeDockMagnification: NSWindowController, NSMenuDelegate {
    private weak var dock: NativeDockController?
    private let surface = MagnificationSurface()
    private let artwork = NSView()
    private let hoverLabel = NativeDockTooltip()
    private let tiles: [NativeDockItemView]
    private var images: [CALayer] = []
    private var dots: [CALayer] = []
    private var folderGlass: [NSView?] = []
    private var folderPreviews: [NSImageView?] = []
    private var hitRects: [NSRect] {
        images.indices.map { NativeDockWave.hitRect(artwork: visibleFrame(at: $0), tileWidth: widths[$0]) }
    }
    private var widths: [CGFloat] = []
    private var baseRects: [NSRect] = []
    private var dotY: [CGFloat] = []
    private var pressedIndex: Int?
    private var pressedRect = NSRect.zero
    private var startPoint = NSPoint.zero
    private var dragging = false
    private var acceptsPointer = false
    var menuIsOpen = false
    private var entryUntil: CFTimeInterval = 0
    private let backdrop = DockGlassRoot.makeMaterial(containing: NSView())
    private let settings = NSButton()
    private var restingBar = NSRect.zero
    private var restingSettings = NSRect.zero
    static let entryDuration = NativeDockWave.entryDuration
    static let exitDuration = NativeDockWave.exitDuration

    init(dock: NativeDockController, tiles: [NativeDockItemView], settings originalSettings: NSButton, bar: NSRect) {
        self.dock = dock; self.tiles = tiles
        let screen = dock.window?.screen?.frame ?? bar
        // A revealing panel is still travelling from its hidden frame. Attach at
        // its current origin, then let child-window movement follow the parent.
        // Mixing the destination origin with current item coordinates clips the
        // entire row below this window for the lifetime of the overlay.
        let parentFrame = dock.window?.frame ?? bar
        let frame = NativeDockWave.overlayFrame(parent: parentFrame, screen: screen)
        let panel = DesktopDockPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Dock Magnification"
        panel.isFloatingPanel = true
        panel.allowsToolTipsWhenApplicationIsInactive = true
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        surface.owner = self; surface.wantsLayer = true
        surface.setAccessibilityElement(true)
        surface.setAccessibilityRole(.group)
        surface.setAccessibilityLabel("Magnified dock")
        panel.contentView = surface
        surface.layer?.masksToBounds = false
        surface.appearance = dock.window?.contentView?.effectiveAppearance
        restingBar = NSRect(x: parentFrame.minX - frame.minX, y: 0, width: bar.width, height: bar.height)
        restingSettings = originalSettings.convert(originalSettings.bounds, to: nil).offsetBy(dx: parentFrame.minX - frame.minX, dy: 0)
        if let appearance = dock.profile?.appearance { DockGlassRoot.configure(backdrop, appearance: appearance) }
        backdrop.frame = restingBar
        surface.addSubview(backdrop)
        // Keep cached artwork in a sibling view above the material. AppKit
        // reorders view-backed layers, so raw sublayers on surface can end up
        // behind the glass and become blurred with the desktop.
        artwork.frame = surface.bounds; artwork.autoresizingMask = [.width, .height]
        artwork.wantsLayer = true; artwork.layer?.masksToBounds = false
        surface.addSubview(artwork)
        settings.image = originalSettings.image; settings.isBordered = false
        settings.bezelStyle = .regularSquare; settings.contentTintColor = .secondaryLabelColor
        settings.setAccessibilityLabel("Dock settings"); settings.toolTip = originalSettings.toolTip
        settings.target = self; settings.action = #selector(showSettingsMenu)
        settings.frame = restingSettings
        surface.addSubview(settings)
        for tile in tiles {
            let converted = tile.convert(tile.bounds, to: nil)
            let screenRect = converted.offsetBy(dx: parentFrame.minX, dy: parentFrame.minY)
            widths.append(tile.bounds.width)
            let widget = tile.item.kind == .widget || tile.item.kind == .spacer
            let side = min(tile.iconSize, tile.bounds.width - 2, tile.bounds.height - 5)
            baseRects.append(widget ? screenRect.offsetBy(dx: -frame.minX, dy: -frame.minY)
                : NSRect(x: screenRect.midX - frame.minX - side / 2,
                         y: screenRect.minY - frame.minY + (tile.bounds.height + 5 - side) / 2,
                         width: side, height: side))
            dotY.append(screenRect.minY - frame.minY)
            // Glass owns its preview, just as in the resting tile. An empty
            // material beneath a separate artwork layer can be culled by AppKit
            // when this transparent child window becomes the visible dock.
            let preview = tile.item.kind == .folder ? NSImageView(image: NativeApplications.icon(for: tile.item)) : nil
            preview?.imageScaling = .scaleProportionallyUpOrDown
            let glass = preview.map { DockGlassRoot.makeFolderMaterial(containing: $0) }
            if let glass {
                glass.frame = baseRects.last!
                surface.addSubview(glass, positioned: .above, relativeTo: artwork)
                glass.layoutSubtreeIfNeeded()
            }
            folderGlass.append(glass)
            folderPreviews.append(preview)
            let image = CALayer()
            image.contentsGravity = .resizeAspect
            image.contentsScale = panel.backingScaleFactor
            image.contents = Self.artwork(for: tile)
            image.isHidden = preview != nil
            artwork.layer?.addSublayer(image); images.append(image)
            let dot = CALayer(); dot.backgroundColor = NSColor.labelColor.withAlphaComponent(0.7).cgColor
            dot.cornerRadius = 1.5; dot.isHidden = !NativeApplications.isRunning(tile.item)
            artwork.layer?.addSublayer(dot); dots.append(dot)
        }
        hoverLabel.isHidden = true
        surface.addSubview(hoverLabel)
        update(at: NSEvent.mouseLocation, animated: false, magnified: false)
        dock.window?.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()
    }
    var hasVisibleContent: Bool {
        !images.isEmpty && images.allSatisfy { $0.contents != nil && $0.frame.intersects(surface.bounds) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func close() {
        if let window { dock?.window?.removeChildWindow(window) }
        super.close()
    }
    private static func artwork(for tile: NativeDockItemView) -> CGImage? {
        if tile.item.kind == .widget || tile.item.kind == .spacer { return tile.snapshotArtwork() }
        let icon = NativeApplications.icon(for: tile.item)
        var rect = NSRect(x: 0, y: 0, width: 192, height: 192)
        return icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    func refreshItems() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, tile) in tiles.enumerated() {
            images[index].contents = Self.artwork(for: tile)
            folderPreviews[index]?.image = NativeApplications.icon(for: tile.item)
        }
        CATransaction.commit()
        refreshRunningIndicators()
    }

    func refreshWidgets() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, tile) in tiles.enumerated() where tile.item.kind == .widget {
            images[index].contents = tile.snapshotArtwork()
        }
        CATransaction.commit()
    }
    func contains(_ screenPoint: NSPoint) -> Bool {
        guard let window else { return false }
        let local = window.convertPoint(fromScreen: screenPoint)
        return restingBar.contains(local) || hitRects.contains { $0.contains(local) }
    }
    private func visibleFrame(at index: Int) -> NSRect {
        images[index].presentation()?.frame ?? images[index].frame
    }
    func updatePointerRouting(at screenPoint: NSPoint) {
        // An icon may finish animating beneath a stationary pointer. Routing
        // must catch up even when no new mouseMoved event is delivered.
        guard pressedIndex == nil, !dragging, !menuIsOpen else { return }
        window?.ignoresMouseEvents = !acceptsPointer || !contains(screenPoint)
    }
    func update(at screenPoint: NSPoint, animated: Bool = true, magnified: Bool = true) {
        guard let window, !menuIsOpen, !dragging, pressedIndex == nil else { return }
        acceptsPointer = magnified
        let x = screenPoint.x - window.frame.minX
        let frames = NativeDockWave.layout(base: baseRects,
            magnifiable: tiles.map { $0.item.kind != .widget && $0.item.kind != .spacer },
            pointerX: magnified ? x : nil, pointerY: screenPoint.y - window.frame.minY)
        let now = CACurrentMediaTime()
        if magnified && entryUntil == 0 { entryUntil = now + Self.entryDuration }
        let duration: TimeInterval
        if !animated || NativeMotion.reducesMotion { duration = 0 }
        else if !magnified { duration = Self.exitDuration; entryUntil = 0 }
        else { duration = max(NativeDockWave.trackingDuration, entryUntil - now) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for index in tiles.indices {
            let rect = frames[index]
            NativeDockWave.move(images[index], to: rect, duration: duration)
            if let glass = folderGlass[index] {
                NativeDockWave.move(glass, to: rect, duration: duration)
                glass.layoutSubtreeIfNeeded()
            }
            NativeDockWave.move(dots[index], to: NSRect(x: rect.midX - 1.5, y: dotY[index], width: 3, height: 3), duration: duration)
        }
        updatePointerRouting(at: screenPoint)
        let point = window.convertPoint(fromScreen: screenPoint)
        let title = tooltipTitle(at: point)
        if !title.isEmpty, let index = index(at: point) {
            hoverLabel.title = title
            let size = hoverLabel.fittingSize
            let anchor = images[index].frame
            hoverLabel.frame = NSRect(x: min(max(8, anchor.midX - size.width / 2), surface.bounds.width - size.width - 8),
                y: min(anchor.maxY + 10, surface.bounds.height - size.height - 4), width: size.width, height: size.height)
            hoverLabel.isHidden = false
        } else { hoverLabel.isHidden = true }
        CATransaction.commit()
    }
    func popoverAnchor(for itemID: UUID) -> (view: NSView, rect: NSRect)? {
        guard let index = tiles.firstIndex(where: { $0.item.id == itemID }) else { return nil }
        hoverLabel.isHidden = true
        return (surface, visibleFrame(at: index))
    }

    @objc private func showSettingsMenu() {
        guard let dock else { return }
        let menu = dock.menu(for: nil)
        menu.delegate = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: settings.bounds.maxY + 4), in: settings)
    }

    func refreshRunningIndicators() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for index in tiles.indices { dots[index].isHidden = !NativeApplications.isRunning(tiles[index].item) }
        CATransaction.commit()
    }

    func tooltipTitle(at point: NSPoint) -> String {
        guard acceptsPointer, !dragging, !menuIsOpen, pressedIndex == nil,
              let index = index(at: point), tiles[index].item.kind != .spacer else { return "" }
        return tiles[index].toolTip ?? tiles[index].item.title
    }

    fileprivate func mouseMoved() { dock?.updatePointer() }
    private func index(at point: NSPoint) -> Int? {
        // Padded targets can overlap slightly; visible artwork takes priority.
        if let index = images.indices.first(where: { visibleFrame(at: $0).contains(point) }) { return index }
        let hits = hitRects
        return hits.indices.filter { hits[$0].contains(point) }
            .min { abs(visibleFrame(at: $0).midX - point.x) < abs(visibleFrame(at: $1).midX - point.x) }
    }
    private func index(at event: NSEvent) -> Int? { index(at: event.locationInWindow) }
    fileprivate func handlePress(_ event: NSEvent) {
        hoverLabel.isHidden = true
        pressedIndex = index(at: event)
        startPoint = event.locationInWindow; dragging = false
        if let index = pressedIndex {
            pressedRect = hitRects[index]
            showPress(true, at: index)
        }
    }

    private func showPress(_ pressed: Bool, at index: Int) {
        let layer = images[index]
        if pressed {
            // A press can arrive mid-hover. Freeze both pieces at the visible
            // frame before applying the shared shrink, rather than at the target.
            let frame = visibleFrame(at: index)
            NativeDockWave.move(layer, to: frame, duration: 0)
            if let glass = folderGlass[index] { NativeDockWave.move(glass, to: frame, duration: 0) }
        }
        let scale: CGFloat = pressed ? (tiles[index].item.kind == .widget ? 0.985 : 0.9) : 1
        let transform = NativeMotion.reducesMotion ? CATransform3DIdentity : CATransform3DMakeScale(scale, scale, 1)
        let fromTransform = layer.presentation()?.transform ?? layer.transform
        let fromOpacity = layer.presentation()?.opacity ?? layer.opacity
        let duration: TimeInterval = NativeMotion.reducesMotion ? 0 : (pressed ? 0.07 : 0.16)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if let glass = folderGlass[index] {
            // Scale around the artwork's center, irrespective of the anchor point
            // AppKit uses for its view-backed material layer.
            let size = layer.bounds.size
            let visualScale: CGFloat = NativeMotion.reducesMotion ? 1 : scale
            let frame = CGRect(x: layer.position.x - size.width * visualScale / 2,
                               y: layer.position.y - size.height * visualScale / 2,
                               width: size.width * visualScale, height: size.height * visualScale)
            NativeDockWave.move(glass, to: frame, duration: duration)
            glass.alphaValue = pressed ? 0.72 : 1
        }
        layer.transform = transform
        layer.opacity = pressed ? 0.72 : 1
        if !NativeMotion.reducesMotion {
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = NSValue(caTransform3D: fromTransform)
            animation.toValue = NSValue(caTransform3D: transform)
            animation.duration = duration
            animation.timingFunction = NativeDockWave.timingFunction
            layer.add(animation, forKey: "pressTransform")
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = fromOpacity; opacity.toValue = layer.opacity
            opacity.duration = animation.duration
            layer.add(opacity, forKey: "pressOpacity")
        }
        CATransaction.commit()
    }
    func showDragSurface() {
        hoverLabel.isHidden = true
        backdrop.isHidden = true
        folderGlass.compactMap { $0 }.forEach { $0.isHidden = true }
        artwork.isHidden = true
        settings.isHidden = true
    }

    fileprivate func handleDrag(_ event: NSEvent) {
        guard let index = pressedIndex, let dock, let window else { return }
        if !dragging {
            guard hypot(event.locationInWindow.x - startPoint.x, event.locationInWindow.y - startPoint.y) > 4,
                  (tiles[index].item.kind == .application || dock.profile?.items.contains(where: { $0.id == tiles[index].item.id }) == true) else { return }
            showPress(false, at: index)
            dragging = true; dock.beginDrag(tiles[index])
        }
        let point = dock.window?.convertPoint(fromScreen: window.convertPoint(toScreen: event.locationInWindow)) ?? .zero
        dock.updateDrag(at: point)
    }
    fileprivate func handleRelease(_ event: NSEvent) {
        guard let index = pressedIndex, let dock, let window else { return }
        pressedIndex = nil
        showPress(false, at: index)
        if dragging {
            let point = dock.window?.convertPoint(fromScreen: window.convertPoint(toScreen: event.locationInWindow)) ?? .zero
            dragging = false
            dock.finishDrag(at: point)
        } else if pressedRect.contains(event.locationInWindow) {
            let item = tiles[index].item
            dock.open(item)
        }
    }
    fileprivate func handleContext(_ event: NSEvent) {
        guard let index = index(at: event), let dock else { return }
        let menu = dock.menu(for: tiles[index].item)
        menu.delegate = self
        NSMenu.popUpContextMenu(menu, with: event, for: surface)
    }
    func menuWillOpen(_ menu: NSMenu) { hoverLabel.isHidden = true; menuIsOpen = true; dock?.menuWillOpen(menu) }
    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false; dock?.menuDidClose(menu); dock?.updatePointer() }
}

private final class MagnificationSurface: NSView {
    weak var owner: NativeDockMagnification?
    private var tracking: NSTrackingArea?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit is NSButton ? hit : self
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseMoved(with event: NSEvent) { owner?.mouseMoved() }
    override func mouseEntered(with event: NSEvent) { owner?.mouseMoved() }
    override func mouseExited(with event: NSEvent) { owner?.mouseMoved() }
    override func mouseDown(with event: NSEvent) { owner?.handlePress(event) }
    override func mouseDragged(with event: NSEvent) { owner?.handleDrag(event) }
    override func mouseUp(with event: NSEvent) { owner?.handleRelease(event) }
    override func rightMouseDown(with event: NSEvent) { owner?.handleContext(event) }
}
#endif
