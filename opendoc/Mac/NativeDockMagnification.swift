#if os(macOS)
import AppKit
import QuartzCore

/// Enlarges the window around the existing dock hierarchy. Icons, folder glass,
/// and widget content remain the same native views throughout hover and hiding.
final class NativeDockMagnification: NSWindowController, NSMenuDelegate {
    private weak var dock: NativeDockController?
    private let surface = MagnificationSurface()
    private let hoverLabel = NativeDockTooltip()
    private let tiles: [NativeDockItemView]
    private let root: NSView
    private let originalRootFrame: NSRect
    private let originalAutoresizing: NSView.AutoresizingMask
    private var clipping: [(NSView, Bool)] = []
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
    static let entryDuration = NativeDockWave.entryDuration
    static let exitDuration = NativeDockWave.exitDuration

    init(dock: NativeDockController, tiles: [NativeDockItemView], root: NSView, bar: NSRect) {
        self.dock = dock; self.tiles = tiles
        self.root = root
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
        // Preserve the full material hierarchy, including the folder glass's
        // original parent. A sibling glass view in another window is not an
        // equivalent rendering of a folder embedded in the dock's material.
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
            // The expanded child window supplies headroom. Keep the scroll view
            // and glass hierarchy intact, allowing artwork to lift above it.
            var ancestor: NSView? = view.superview
            while let current = ancestor, current !== surface {
                if !clipping.contains(where: { $0.0 === current }) {
                    clipping.append((current, current.clipsToBounds))
                    current.clipsToBounds = false
                }
                ancestor = current.superview
            }
        }
        hoverLabel.isHidden = true
        surface.addSubview(hoverLabel)
        update(at: NSEvent.mouseLocation, animated: false, magnified: false)
        dock.window?.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()
    }
    var hasVisibleContent: Bool {
        !tiles.isEmpty && baseRects.allSatisfy { $0.width > 0 && $0.height > 0 && $0.intersects(surface.bounds) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    private func restoreDock() {
        guard !restored else { return }
        restored = true
        for (index, tile) in tiles.enumerated() {
            tile.animationView.layer?.removeAllAnimations()
            tile.animationView.frame = originalArtworkFrames[index]
            tile.resetArtwork()
        }
        clipping.forEach { $0.0.clipsToBounds = $0.1 }
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

    func contains(_ screenPoint: NSPoint) -> Bool {
        guard let window else { return false }
        let local = window.convertPoint(fromScreen: screenPoint)
        return restingBar.contains(local) || hitRects.contains { $0.contains(local) }
    }
    private func visibleFrame(at index: Int) -> NSRect {
        let view = tiles[index].animationView
        let frame = view.layer?.presentation()?.frame ?? view.frame
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
        for index in tiles.indices {
            moveArtwork(at: index, to: frames[index], duration: duration)
        }
        updatePointerRouting(at: screenPoint)
        let point = window.convertPoint(fromScreen: screenPoint)
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
        guard let parent = view.superview else { return }
        let destination = parent.convert(frame, from: surface)
        guard view.frame != destination || duration == 0 else { return }
        if duration == 0 {
            view.layer?.removeAllAnimations()
            view.frame = destination
            view.layoutSubtreeIfNeeded()
        } else {
            NativeMotion.animate(duration, timingFunction: NativeDockWave.timingFunction) {
                view.animator().frame = destination
            }
        }
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
            ? (tiles[index].item.kind == .widget ? 0.985 : 0.9) : 1
        let rect = pressedArtwork.insetBy(dx: pressedArtwork.width * (1 - scale) / 2,
                                          dy: pressedArtwork.height * (1 - scale) / 2)
        let duration: TimeInterval = NativeMotion.reducesMotion ? 0 : (pressed ? 0.07 : 0.16)
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
