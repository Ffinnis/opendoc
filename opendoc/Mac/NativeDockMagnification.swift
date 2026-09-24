#if os(macOS)
import AppKit
import QuartzCore

/// Enlarges the window around the existing dock hierarchy. Icons, folder tiles,
/// and widget content remain the same native views throughout hover and hiding.
/// The shelf material widens with the row, and the overlay carries the window
/// shadow so the dock never loses it while magnified.
final class NativeDockMagnification: NSWindowController, NSMenuDelegate {
    private weak var dock: NativeDockController?
    private let surface = MagnificationSurface()
    private let hoverLabel = NativeDockTooltip()
    private let tiles: [NativeDockItemView]
    private let root: DockGlassRoot
    private weak var trailing: NSView?
    private var trailingOrigin: NSPoint?
    private let originalRootFrame: NSRect
    private let originalAutoresizing: NSView.AutoresizingMask
    private var restored = false
    private var hitRects: [NSRect] {
        tiles.indices.map { NativeDockWave.hitRect(artwork: visibleFrame(at: $0), tileWidth: widths[$0]) }
    }
    private var widths: [CGFloat] = []
    private var baseRects: [NSRect] = []
    private var originalArtworkFrames: [NSRect] = []
    private var pressedIndex: Int?
    private var pressedRect = NSRect.zero
    private var pressedArtwork = NSRect.zero
    private var startPoint = NSPoint.zero
    private var dragging = false
    private var acceptsPointer = false
    var menuIsOpen = false
    private var entryUntil: CFTimeInterval = 0
    private var restingBar = NSRect.zero
    private var shelfLink: CADisplayLink?
    private var shadowWidth: CGFloat = 0
    private var trackUntil: CFTimeInterval = 0
    private var lastPointer = NSPoint.zero
    static let entryDuration = NativeDockWave.entryDuration
    static let exitDuration = NativeDockWave.exitDuration

    init(dock: NativeDockController, tiles: [NativeDockItemView], root: DockGlassRoot, trailing: NSView?, bar: NSRect) {
        self.dock = dock; self.tiles = tiles
        self.root = root
        self.trailing = trailing
        trailingOrigin = trailing?.frame.origin
        originalRootFrame = root.frame
        originalAutoresizing = root.autoresizingMask
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
        panel.backgroundColor = .clear; panel.isOpaque = false
        // The shelf moves into this window, so its shadow moves with it.
        panel.hasShadow = true
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
        // Keep the original row and its artwork hosts. The shelf stays behind
        // them; opening the larger window never substitutes another renderer.
        dock.window?.contentView = NSView(frame: originalRootFrame)
        root.autoresizingMask = []
        root.frame = restingBar
        surface.addSubview(root)
        root.layoutSubtreeIfNeeded()
        for tile in tiles {
            widths.append(tile.bounds.width)
            let view = tile.animationView
            originalArtworkFrames.append(view.frame)
            baseRects.append(view.convert(view.bounds, to: surface))
            tile.animatesArtwork = true
        }
        hoverLabel.isHidden = true
        surface.addSubview(hoverLabel)
        dock.window?.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()
        // AppKit synchronizes backing-layer geometry on the first display in a
        // new window. Finish that synchronization before applying hover transforms.
        surface.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        CATransaction.flush()
        update(at: NSEvent.mouseLocation, animated: false, magnified: false)
    }
    var hasVisibleContent: Bool {
        !tiles.isEmpty && baseRects.allSatisfy { $0.width > 0 && $0.height > 0 && $0.intersects(surface.bounds) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    private func restoreDock() {
        guard !restored else { return }
        restored = true
        stopShelfTracking()
        for (index, tile) in tiles.enumerated() {
            tile.animationView.layer?.removeAllAnimations()
            tile.animationView.layer?.transform = CATransform3DIdentity
            tile.animationView.frame = originalArtworkFrames[index]
            tile.resetArtwork()
        }
        root.materialFrameOverride = nil
        setTrailingShift(0)
        root.removeFromSuperview()
        root.autoresizingMask = originalAutoresizing
        dock?.window?.contentView = root
        root.frame = originalRootFrame
        root.layoutSubtreeIfNeeded()
    }
    override func close() {
        restoreDock()
        if let window { dock?.window?.removeChildWindow(window) }
        super.close()
    }
    func refreshItems() { refreshRunningIndicators() }

    /// The shelf as currently drawn, in surface coordinates.
    var shelfFrame: NSRect { root.convert(root.materialFrameOverride ?? root.bounds, to: surface) }

    func contains(_ screenPoint: NSPoint) -> Bool {
        guard let window else { return false }
        let local = window.convertPoint(fromScreen: screenPoint)
        return restingBar.contains(local) || shelfFrame.contains(local) || hitRects.contains { $0.contains(local) }
    }
    private func visibleFrame(at index: Int) -> NSRect {
        let view = tiles[index].animationView
        let frame = view.layer?.presentation()?.frame ?? view.layer?.frame ?? view.frame
        return view.superview?.convert(frame, to: surface) ?? frame
    }
    func updatePointerRouting(at screenPoint: NSPoint) {
        // An icon may finish animating beneath a stationary pointer. Routing
        // must catch up even when no new mouseMoved event is delivered.
        guard pressedIndex == nil, !dragging, !menuIsOpen else { return }
        window?.ignoresMouseEvents = !acceptsPointer || !contains(screenPoint)
    }
    func update(at screenPoint: NSPoint, animated: Bool = true, magnified: Bool = true) {
        guard let window, !restored, !menuIsOpen, !dragging, pressedIndex == nil else { return }
        acceptsPointer = magnified
        lastPointer = screenPoint
        let x = screenPoint.x - window.frame.minX
        let magnifiable = tiles.map { $0.item.kind != .widget && $0.item.kind != .spacer }
        let frames = NativeDockWave.clamp(
            NativeDockWave.layout(base: baseRects, magnifiable: magnifiable,
                                  pointerX: magnified ? x : nil, pointerY: screenPoint.y - window.frame.minY),
            to: surface.bounds, inset: 8)
        let now = CACurrentMediaTime()
        if magnified && entryUntil == 0 { entryUntil = now + Self.entryDuration }
        let duration: TimeInterval
        if !animated || NativeMotion.reducesMotion { duration = 0 }
        else if !magnified { duration = NativeDockWave.exitDuration; entryUntil = 0 }
        else { duration = max(NativeDockWave.trackingDuration, entryUntil - now) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in tiles.indices {
            moveArtwork(at: index, to: frames[index], duration: duration)
        }
        CATransaction.commit()
        trackShelf(for: duration)
        updatePointerRouting(at: screenPoint)
        updateHoverLabel()
    }
    /// Icons keep moving after the last pointer event while their springs
    /// settle. The label follows the item that ends up under the pointer.
    private func updateHoverLabel() {
        guard let window, !restored else { return }
        let point = window.convertPoint(fromScreen: lastPointer)
        let title = tooltipTitle(at: point)
        if !title.isEmpty, let index = index(at: point) {
            hoverLabel.title = title
            let size = hoverLabel.fittingSize
            let anchor = visibleFrame(at: index)
            hoverLabel.frame = NSRect(x: min(max(8, anchor.midX - size.width / 2), surface.bounds.width - size.width - 8),
                y: min(anchor.maxY + 10, surface.bounds.height - size.height - 4), width: size.width, height: size.height)
            hoverLabel.isHidden = false
        } else { hoverLabel.isHidden = true }
    }
    private func moveArtwork(at index: Int, to frame: NSRect, duration: TimeInterval) {
        let view = tiles[index].animationView
        guard let parent = view.superview, let layer = view.layer else { return }
        let destination = parent.convert(frame, from: surface)
        NativeDockWave.transform(layer, from: originalArtworkFrames[index], to: destination, duration: duration)
    }

    // MARK: Shelf tracking

    /// Follows the icons' presentation frames while they animate, so the glass
    /// hugs the row on every display refresh and the shadow follows its shape.
    private func trackShelf(for duration: TimeInterval) {
        trackUntil = max(trackUntil, CACurrentMediaTime() + duration)
        shelfTick()
        guard duration > 0, shelfLink == nil else { return }
        let link = surface.displayLink(target: self, selector: #selector(shelfFrame(_:)))
        link.add(to: .main, forMode: .common)
        shelfLink = link
    }
    @objc private func shelfFrame(_ link: CADisplayLink) { shelfTick() }
    private func stopShelfTracking() {
        shelfLink?.invalidate(); shelfLink = nil
    }
    private func shelfTick() {
        guard !restored else { stopShelfTracking(); return }
        let settled = CACurrentMediaTime() >= trackUntil
        var left: CGFloat = 0, right: CGFloat = 0
        for index in tiles.indices {
            let frame = visibleFrame(at: index)
            left = min(left, frame.minX - baseRects[index].minX)
            right = max(right, frame.maxX - baseRects[index].maxX)
        }
        // Whole points avoid re-rendering the glass for sub-pixel changes.
        left = left.rounded(.down); right = right.rounded(.up)
        let override = left == 0 && right == 0 ? nil
            : NSRect(x: left, y: 0, width: root.bounds.width + right - left, height: root.bounds.height)
        root.materialFrameOverride = override
        setTrailingShift(right)
        // Recomputing a window shadow is expensive. Follow large changes and
        // the final shape rather than every frame.
        let width = override?.width ?? root.bounds.width
        if settled || abs(width - shadowWidth) >= 6 {
            shadowWidth = width
            window?.invalidateShadow()
        }
        if !menuIsOpen, pressedIndex == nil, !dragging { updateHoverLabel() }
        if settled { stopShelfTracking() }
    }
    /// Moves the frame, not a layer transform, so its click target follows.
    private func setTrailingShift(_ shift: CGFloat) {
        guard let trailing, let origin = trailingOrigin else { return }
        let target = NSPoint(x: origin.x + shift, y: origin.y)
        if trailing.frame.origin != target { trailing.setFrameOrigin(target) }
    }

    func popoverAnchor(for itemID: UUID) -> (view: NSView, rect: NSRect)? {
        guard let index = tiles.firstIndex(where: { $0.item.id == itemID }) else { return nil }
        hoverLabel.isHidden = true
        return (surface, visibleFrame(at: index))
    }

    func refreshRunningIndicators() { tiles.forEach { $0.refreshRunningIndicator() } }

    func tooltipTitle(at point: NSPoint) -> String {
        guard acceptsPointer, !dragging, !menuIsOpen, pressedIndex == nil,
              let index = index(at: point), tiles[index].item.kind != .spacer else { return "" }
        return tiles[index].toolTip ?? tiles[index].item.title
    }

    fileprivate func mouseMoved() { dock?.updatePointer() }
    private func index(at point: NSPoint) -> Int? {
        // Padded targets can overlap slightly; visible artwork takes priority.
        if let index = tiles.indices.first(where: { visibleFrame(at: $0).contains(point) }) { return index }
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
        if pressed { pressedArtwork = visibleFrame(at: index) }
        let scale: CGFloat = pressed && !NativeMotion.reducesMotion
            ? (tiles[index].item.kind == .widget ? 0.985 : 0.92) : 1
        let rect = pressedArtwork.insetBy(dx: pressedArtwork.width * (1 - scale) / 2,
                                          dy: pressedArtwork.height * (1 - scale) / 2)
        let duration: TimeInterval = NativeMotion.reducesMotion ? 0 : (pressed ? 0.1 : 0.22)
        moveArtwork(at: index, to: rect, duration: duration)
        NativeMotion.animate(duration) { tiles[index].animationView.animator().alphaValue = pressed ? 0.72 : 1 }
    }
    func showDragSurface() {
        hoverLabel.isHidden = true
        restoreDock()
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
        if dragging {
            let point = dock.window?.convertPoint(fromScreen: window.convertPoint(toScreen: event.locationInWindow)) ?? .zero
            dragging = false
            dock.finishDrag(at: point)
        } else {
            showPress(false, at: index)
            guard pressedRect.contains(event.locationInWindow) else { return }
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
