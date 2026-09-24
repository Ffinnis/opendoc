#if os(macOS)
import AppKit
import UniformTypeIdentifiers

final class DesktopDockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class NativeDockController: NSWindowController, NSMenuDelegate {
    let profileID: UUID
    let store: DockStore
    weak var application: MacApplication?
    var profile: DockProfile? { store.archive.profiles.first { $0.id == profileID } }
    private let root = DockGlassRoot()
    private var itemViews: [NativeDockItemView] = []
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var editor: NativeWidgetEditor?
    private(set) var folderController: NativeFolderController?
    private var widgetLibrary: NativeWidgetLibrary?
    private var groupTarget: UUID?
    private var groupCandidate: (UUID, Date)?
    private var groupTimer: Timer?
    private let dockContent = FlippedNativeView()
    private var settingsButton: NSButton?
    private var runningIDs: [String: UUID] = [:]
    var interacting = false
    private var hidden = false
    private var draggedView: NativeDockItemView?
    private var dragImage: NSImageView?
    private var dropTarget: (UUID, Bool)?
    private var contentSize = NSSize(width: 600, height: 64)
    private var visibleFrame = NSRect.zero
    private var revealDwell = NativeDockVisibility.RevealDwell()
    private var hideTimer: Timer?
    private var pointerTimer: Timer?
    private var localPointerMonitor: Any?
    private var globalPointerMonitor: Any?
    private var lastPointer: NSPoint?
    private var lastHoverActive = false
    private var magnification: NativeDockMagnification?
    private var pendingWorkspaceReload = false
    private var magnificationExit: Timer?
    private var previewUntil = Date.distantPast
    private var popupOpen: Bool { folderController?.isShown == true || editor?.isShown == true }
    private var dragLayout: [ObjectIdentifier: NSRect] = [:]
    private var landingPreview: NSView?
    private var dropFrame: NSRect?
    private let hoverLabel = NativeDockHoverLabel()
    private var chromeVisible = false
    private var launchObservers: [UUID: NSKeyValueObservation] = [:]
    private var launchTimers: [UUID: Timer] = [:]

    init(profileID: UUID, store: DockStore, application: MacApplication) {
        self.profileID = profileID
        self.store = store
        self.application = application
        let panel = DesktopDockPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 64), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.allowsToolTipsWhenApplicationIsInactive = true
        super.init(window: panel)
        panel.contentView = root
        root.controller = self
        reload()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.magnification != nil {
                        self.pendingWorkspaceReload = true
                        self.magnification?.refreshRunningIndicators()
                    } else { self.reload() }
                }
            })
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.endMagnification()
                self?.reload()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.hidden, self.window?.isVisible == true else { return }
                let now = Date()
                self.itemViews.forEach { $0.refreshIfNeeded(at: now) }
            }
        }
    }
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        pointerTimer?.invalidate()
        stopPointerMonitors()
        // Transparent approach space and native controls do not reliably send
        // mouseMoved to the row. Observe motion without intercepting those events.
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        // Edge detection only. Hover animation receives native mouse-move events below.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }
        pointerTimer = timer
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        scheduleHide()
    }
    override func close() {
        endMagnification()
        hoverLabel.hide()
        launchTimers.values.forEach { $0.invalidate() }
        launchTimers = [:]; launchObservers = [:]
        pointerTimer?.invalidate(); hideTimer?.invalidate()
        stopPointerMonitors()
        editor?.close(); folderController?.close()
        super.close()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit {
        timer?.invalidate()
        pointerTimer?.invalidate()
        hideTimer?.invalidate()
        groupTimer?.invalidate()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
    }

    private func stopPointerMonitors() {
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
        localPointerMonitor = nil; globalPointerMonitor = nil
    }

    private func pointerMoved() {
        guard !hidden, magnification != nil || visibleFrame.insetBy(dx: -120, dy: -120).contains(NSEvent.mouseLocation) else { return }
        updatePointer()
    }

    func reload() {
        guard draggedView == nil else { pendingWorkspaceReload = true; return }
        guard let profile else { return }
        window?.title = profile.name
        root.setAccessibilityLabel("\(profile.name) Dock")
        root.appearance = profile.appearance.material == "Dark" ? NSAppearance(named: .darkAqua) : profile.appearance.material == "Light" ? NSAppearance(named: .aqua) : nil
        let vertical = profile.appearance.position != "Bottom"
        let requestedSize = CGFloat(profile.appearance.size)
        let folderApps = Set(profile.items.filter { $0.kind == .folder }.flatMap { $0.children ?? [] }.compactMap(\.applicationURL))
        var displayed = profile.items.filter { $0.applicationURL.map(folderApps.contains) != true }
        if profile.items.contains(where: { $0.kind == .application || $0.kind == .folder }) {
            let running = NativeApplications.unpinnedURLs(
                NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleURL != Bundle.main.bundleURL }.compactMap(\.bundleURL),
                in: profile.items)
            if !running.isEmpty {
                let insertion = displayed.firstIndex(where: { $0.kind == .trash }) ?? displayed.count
                displayed.insert(contentsOf: running.map {
                    var item = NativeApplications.item(for: $0)
                    let path = $0.standardizedFileURL.resolvingSymlinksInPath().path
                    item.id = runningIDs[path] ?? item.id
                    runningIDs[path] = item.id
                    return item
                }, at: insertion)
            }
        }
        let screen = window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let availableLength = screen.map { vertical ? $0.frame.height - 80 : $0.frame.width - 24 } ?? .greatestFiniteMagnitude
        let size = Self.fittingIconSize(items: displayed, requestedSize: requestedSize, vertical: vertical, availableLength: availableLength)
        // Widgets keep their configured height even when neighboring icons shrink.
        let thicknessSize = displayed.contains { $0.kind == .widget } ? requestedSize : size
        let thickness = vertical ? max(84, thicknessSize + 20) : thicknessSize + 22
        root.configure(profile.appearance, cornerRadius: NativeDockStyle.shelfRadius(iconSize: size, thickness: thickness))
        if popupOpen, magnification != nil, displayed.map(\.id) == itemViews.map({ $0.item.id }),
           thickness == (vertical ? contentSize.width : contentSize.height),
           itemViews.allSatisfy({ $0.iconSize == size && $0.vertical == vertical }) {
            for (view, item) in zip(itemViews, displayed) { view.item = item }
            magnification?.refreshItems()
            return
        }
        pendingWorkspaceReload = false
        endMagnification()
        let oldViews = Dictionary(uniqueKeysWithValues: itemViews.map { ($0.item.id, $0) })
        itemViews = displayed.map { item in
            if let existing = oldViews[item.id], existing.iconSize == size, existing.vertical == vertical {
                existing.item = item
                return existing
            }
            let view = NativeDockItemView(item: item, iconSize: size, vertical: vertical)
            view.controller = self
            return view
        }
        for old in oldViews.values where !itemViews.contains(where: { $0 === old }) { old.removeFromSuperview() }
        let frames = Self.rowFrames(lengths: itemViews.map { Self.length(of: $0.item, iconSize: size, vertical: vertical) }, thickness: thickness, vertical: vertical)
        for (view, frame) in zip(itemViews, frames) {
            if view.superview == nil {
                view.frame = frame
                dockContent.addSubview(view)
                view.alphaValue = 0
                view.layer?.transform = CATransform3DMakeScale(0.6, 0.6, 1)
                NativeMotion.animate(0.18) { view.animator().alphaValue = 1 }
                let grow = NativeMotion.spring("transform", duration: 0.3, bounce: 0.25)
                grow.fromValue = NSValue(caTransform3D: CATransform3DMakeScale(0.6, 0.6, 1))
                grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
                view.layer?.transform = CATransform3DIdentity
                if !NativeMotion.reducesMotion { view.layer?.add(grow, forKey: "dockInsert") }
            } else if view.frame != frame {
                NativeMotion.animate(0.22) { view.animator().frame = frame }
            }
        }
        var offset: CGFloat = frames.last.map { vertical ? $0.maxY + 3 : $0.maxX + 3 } ?? 8
        settingsButton?.removeFromSuperview()
        let settings = NSButton(image: NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Dock settings")!, target: self, action: #selector(showMenu(_:)))
        settings.bezelStyle = .regularSquare
        settings.isBordered = false
        settings.wantsLayer = true
        settings.contentTintColor = .secondaryLabelColor
        settings.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        settings.toolTip = "Add widgets or edit this dock"
        settings.setAccessibilityLabel("Dock settings")
        // Chrome stays quiet like the system Dock: faint at rest so the end of
        // the shelf reads as a control, full strength while the pointer is over it.
        settings.alphaValue = chromeVisible ? 1 : NativeDockStyle.restingChromeAlpha
        let button = NativeDockStyle.settingsButtonWidth
        settings.frame = vertical ? NSRect(x: 8, y: offset + 1, width: thickness - 16, height: button) : NSRect(x: offset + 1, y: 10, width: button, height: thickness - 20)
        dockContent.addSubview(settings)
        let ordered: [NSView] = itemViews + [settings] + (landingPreview.map { [$0] } ?? [])
        dockContent.subviews = ordered
        settingsButton = settings
        offset += NativeDockStyle.trailingLength
        contentSize = vertical ? NSSize(width: thickness, height: offset) : NSSize(width: offset, height: thickness)
        dockContent.frame = NSRect(origin: .zero, size: contentSize)
        root.setDocumentView(dockContent)
        positionPanel(animated: window?.isVisible == true && !hidden)
        root.autoHide = profile.appearance.autoHide
    }

    static func length(of item: DockItem, iconSize: CGFloat, vertical: Bool) -> CGFloat {
        switch item.kind {
        case .widget: return vertical ? 76 : [.note, .custom].contains(item.widget) ? 146 : item.widget == .calendar ? 122 : 126
        case .spacer: return 12
        default: return iconSize + 7
        }
    }

    /// Fit the displayed row, including running apps, spacing and settings.
    /// Keep a usable minimum; larger collections remain scrollable. This is
    /// presentation only, so removing items restores the user's chosen size.
    static func fittingIconSize(items: [DockItem], requestedSize: CGFloat, vertical: Bool, availableLength: CGFloat) -> CGFloat {
        let iconCount = items.filter { $0.kind != .widget && $0.kind != .spacer }.count
        guard iconCount > 0 else { return requestedSize }
        let fixedLength = 8 + NativeDockStyle.trailingLength + items.reduce(CGFloat.zero) {
            $0 + length(of: $1, iconSize: 0, vertical: vertical) + 3
        }
        let fitting = ((availableLength - fixedLength) / CGFloat(iconCount)).rounded(.down)
        return min(requestedSize, max(24, fitting))
    }

    /// Tile frames for a row, in the flipped content coordinates. `gap` opens
    /// room for a dragged item before the tile at that index.
    static func rowFrames(lengths: [CGFloat], thickness: CGFloat, vertical: Bool, gap: (index: Int, length: CGFloat)? = nil) -> [NSRect] {
        var offset: CGFloat = 8
        return lengths.enumerated().map { index, length in
            if let gap, gap.index == index { offset += gap.length + 3 }
            defer { offset += length + 3 }
            return vertical ? NSRect(x: 6, y: offset, width: thickness - 12, height: length) : NSRect(x: offset, y: 6, width: length, height: thickness - 12)
        }
    }

    private func setChromeVisible(_ visible: Bool) {
        guard visible != chromeVisible else { return }
        chromeVisible = visible
        guard let settingsButton else { return }
        NativeMotion.animate(visible ? 0.15 : 0.3) { settingsButton.animator().alphaValue = visible ? 1 : NativeDockStyle.restingChromeAlpha }
    }

    func positionPanel(animated: Bool = false) {
        guard let profile, let panel = window, let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        let size = NSSize(width: min(contentSize.width, frame.width - 24), height: min(contentSize.height, frame.height - 80))
        // Offset a second dock on the same edge so profiles don't cover one another.
        let visible = store.archive.profiles.filter { application?.isDockVisible($0.id) == true && $0.appearance.position == profile.appearance.position }
        let lane = visible.firstIndex(where: { $0.id == profileID }) ?? 0
        let laneOffset = visible.prefix(lane).reduce(CGFloat.zero) { offset, preceding in
            let iconSize = CGFloat(preceding.appearance.size)
            return offset + (preceding.appearance.position == "Bottom" ? iconSize + 22 : max(84, iconSize + 20)) + 8
        }
        let padding: CGFloat = 8
        let origin: NSPoint
        switch profile.appearance.position {
        case "Left": origin = NSPoint(x: frame.minX + padding + laneOffset, y: frame.midY - size.height / 2)
        case "Right": origin = NSPoint(x: frame.maxX - size.width - padding - laneOffset, y: frame.midY - size.height / 2)
        default:
            let systemDockInset: CGFloat = SystemDockSession.isActive ? 0 : max(0, screen.visibleFrame.minY - frame.minY)
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + padding + systemDockInset + laneOffset)
        }
        visibleFrame = NSRect(origin: origin, size: size)
        if !profile.appearance.autoHide { hidden = false }
        let destination = hidden ? hiddenFrame(on: screen) : visibleFrame
        if animated {
            NativeMotion.animate(0.22) { panel.animator().setFrame(destination, display: true) }
        } else { panel.setFrame(destination, display: true) }
    }

    func reveal(animated: Bool = true) {
        revealDwell.reset()
        hideTimer?.invalidate()
        guard visibleFrame != .zero else { return }
        guard hidden else { return }
        hidden = false
        if animated { NativeMotion.animate(0.22) { window?.animator().setFrame(visibleFrame, display: true) } }
        else { window?.setFrame(visibleFrame, display: true) }
    }

    private func hiddenFrame(on screen: NSScreen) -> NSRect {
        NativeDockVisibility.hiddenFrame(visibleFrame, screen: screen.frame, edge: profile?.appearance.position ?? "Bottom")
    }

    private func pointerIsInside(_ point: NSPoint) -> Bool {
        guard let screen = window?.screen ?? NSScreen.main else { return false }
        let edge = profile?.appearance.position ?? "Bottom"
        let area = hidden ? NativeDockVisibility.revealArea(visibleFrame, screen: screen.frame, edge: edge)
            : NativeDockVisibility.activationArea(visibleFrame, screen: screen.frame, edge: edge)
        return area.contains(point) || (!hidden && magnification?.contains(point) == true)
    }

    func updatePointer() {
        guard window?.isVisible == true else { return }
        if previewUntil > Date() { return }
        let point = NSEvent.mouseLocation
        magnification?.updatePointerRouting(at: point)
        let inside = pointerIsInside(point)
        if hidden {
            if popupOpen || interacting || revealDwell.update(isInside: inside, at: ProcessInfo.processInfo.systemUptime) {
                reveal()
            }
        } else {
            revealDwell.reset()
            if inside || popupOpen || interacting { reveal() }
            else { scheduleHide() }
        }
        setChromeVisible(!hidden && (inside || popupOpen || interacting || draggedView != nil))
        if draggedView != nil || magnification?.menuIsOpen == true || popupOpen { hoverLabel.hide(); return }
        // Start the wave outside the visible row at zero influence. Waiting until
        // the pointer crosses the row's edge requests near-maximum size at once.
        // This approach area never reveals a hidden dock or intercepts clicks.
        let approach = profile?.appearance.position == "Bottom"
            ? visibleFrame.insetBy(dx: -120, dy: -120) : visibleFrame
        let hoverActive = !hidden && (approach.contains(point) || magnification?.contains(point) == true) && !interacting && !popupOpen
        guard point != lastPointer || hoverActive != lastHoverActive else { return }
        lastPointer = point; lastHoverActive = hoverActive
        if hoverActive && profile?.appearance.position == "Bottom" && !NativeMotion.reducesMotion {
            magnificationExit?.invalidate(); magnificationExit = nil
            if magnification == nil {
                installMagnification()
            }
            magnification?.update(at: point)
        } else {
            if magnification != nil, magnificationExit == nil {
                magnification?.update(at: point, magnified: false)
                magnificationExit = Timer.scheduledTimer(withTimeInterval: NativeDockMagnification.exitDuration, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        // A launching icon bounces above the shelf, which only
                        // the overlay has room for. Check again once it lands.
                        if self.itemViews.contains(where: \.isLaunching) {
                            self.magnificationExit = nil
                            self.lastPointer = nil
                            return
                        }
                        // An auto-hiding dock keeps the same glass until it has
                        // left the screen, rather than swapping material first.
                        if self.profile?.appearance.autoHide != true { self.endMagnification() }
                    }
                }
            }
            updateHoverLabel(at: point, active: hoverActive && magnification == nil)
        }
    }

    /// The label for docks that are not magnified: side docks, Reduce Motion,
    /// and overflowing rows. Magnified docks label inside their overlay.
    private func updateHoverLabel(at point: NSPoint, active: Bool) {
        guard active, let window, let tile = itemViews.first(where: { tile in
            let local = tile.convert(window.convertPoint(fromScreen: point), from: nil)
            return tile.item.kind != .spacer && tile.bounds.contains(local)
        }) else { hoverLabel.hide(); return }
        let title = tile.toolTip ?? tile.item.title
        if hoverLabel.itemID == tile.item.id, hoverLabel.isShown { return }
        let anchor = window.convertToScreen(tile.convert(tile.bounds, to: nil))
        hoverLabel.show(title, itemID: tile.item.id, anchor: anchor, edge: profile?.appearance.position ?? "Bottom", in: window)
    }

    private func installMagnification() {
        // Overflow docks retain their scrollable row; a partial widget must not
        // be snapshotted outside the viewport into the magnification window.
        guard contentSize.width <= visibleFrame.width, settingsButton != nil, let panel = window else { return }
        // During an animated resize, visibleFrame is the destination while the
        // panel still has its previous size. Do not replace it with a larger or
        // smaller shelf on first hover. The pointer timer retries once settled.
        guard abs(panel.frame.width - visibleFrame.width) < 0.5,
              abs(panel.frame.height - visibleFrame.height) < 0.5 else {
            lastPointer = nil
            return
        }
        root.layoutSubtreeIfNeeded()
        hoverLabel.hide()
        let overlay = NativeDockMagnification(dock: self, tiles: itemViews, root: root, trailing: settingsButton, bar: panel.frame)
        // A failed overlay must never leave an empty glass bar behind.
        guard overlay.hasVisibleContent else { overlay.close(); return }
        magnification = overlay
    }

    func endMagnification() {
        previewUntil = .distantPast
        magnificationExit?.invalidate(); magnificationExit = nil
        magnification?.close(); magnification = nil
        root.alphaValue = 1
        itemViews.forEach { if draggedView !== $0 { $0.alphaValue = 1 } }
        if pendingWorkspaceReload {
            pendingWorkspaceReload = false
            reload()
        }
    }

    func previewMagnification() {
        guard profile?.appearance.position == "Bottom", !NativeMotion.reducesMotion else { reveal(); return }
        endMagnification()
        reveal()
        root.layoutSubtreeIfNeeded()
        previewUntil = Date().addingTimeInterval(4)
        installMagnification()
        magnification?.update(at: NSPoint(x: visibleFrame.midX, y: visibleFrame.minY + 25))
        lastPointer = nil
    }

    func scheduleHide() {
        guard hideTimer?.isValid != true, !hidden, profile?.appearance.autoHide == true, !interacting, !popupOpen else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.interacting, !self.popupOpen, !self.pointerIsInside(NSEvent.mouseLocation), self.profile?.appearance.autoHide == true,
                      let screen = self.window?.screen ?? NSScreen.main else { return }
                self.hidden = true
                self.revealDwell.reset()
                self.hoverLabel.hide()
                self.setChromeVisible(false)
                self.magnification?.update(at: NSEvent.mouseLocation, magnified: false)
                NativeMotion.animate(0.24) {
                    self.window?.animator().setFrame(self.hiddenFrame(on: screen), display: true)
                } completion: { [weak self] in
                    guard let self, self.hidden else { return }
                    self.endMagnification()
                }
            }
        }
    }

    @objc private func showMenu(_ sender: NSButton) {
        let menu = menu(for: nil)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    func menuWillOpen(_ menu: NSMenu) { interacting = true; reveal(animated: false) }
    func menuDidClose(_ menu: NSMenu) { interacting = false; scheduleHide() }

    func addApplicationActions(to menu: NSMenu, for item: DockItem) {
        menu.addItem(NativeMenuAction.item("Open") { [weak self] in
            self?.folderController?.close()
            self?.open(item)
        })
        if NativeApplicationWindows.supportsNewWindow(item) {
            menu.addItem(NativeMenuAction.item("New Window") { [weak self] in self?.openNewWindow(item) })
        }
        if let url = item.applicationURL {
            menu.addItem(NativeMenuAction.item("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            })
        }
        if let url = item.applicationURL,
           let running = NSWorkspace.shared.runningApplications.first(where: {
               $0.bundleURL?.normalizedApplicationURL == url
           }) {
            menu.addItem(.separator())
            menu.addItem(NativeMenuAction.item(running.isHidden ? "Show" : "Hide") {
                if running.isHidden { running.unhide() } else { running.hide() }
            })
            menu.addItem(NativeMenuAction.item("Quit \(item.title)") { running.terminate() })
        }
    }

    func menu(for item: DockItem?) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        if let item {
            if item.kind == .application {
                addApplicationActions(to: menu, for: item)
                menu.addItem(.separator())
            }
            if item.kind == .folder {
                menu.addItem(NativeMenuAction.item("Open Folder") { [weak self] in self?.open(item) })
                menu.addItem(NativeMenuAction.item("Ungroup Applications") { [weak self] in
                    guard let self else { return }
                    do { try store.ungroupFolder(item.id, in: profileID) } catch { application?.report(error.localizedDescription) }
                })
            }
            if item.kind == .application, let profile {
                let folders = NSMenu()
                for folder in profile.items where folder.kind == .folder {
                    folders.addItem(NativeMenuAction.item(folder.title) { [weak self] in
                        guard let self else { return }
                        do { try store.addApplications([item], into: folder.id, in: profileID) } catch { application?.report(error.localizedDescription) }
                    })
                }
                if !folders.items.isEmpty {
                    let move = NSMenuItem(title: "Move to Folder", action: nil, keyEquivalent: "")
                    move.submenu = folders; menu.addItem(move)
                }
            }
            if item.widget == .webValue {
                menu.addItem(NativeMenuAction.item("Refresh Now") { NativeWidgetData.shared.refresh(item) })
            }
            if item.kind == .widget { menu.addItem(NativeMenuAction.item("Edit \(item.title)…") { [weak self] in self?.open(item) }) }
            if profile?.items.contains(where: { $0.id == item.id }) == true {
                menu.addItem(NativeMenuAction.item("Remove from Dock") { [weak self] in self?.remove(item.id) })
            } else if item.kind == .application {
                menu.addItem(NativeMenuAction.item("Keep in Dock") { [weak self] in self?.add(item) })
            }
            menu.addItem(.separator())
        }
        menu.addItem(NativeMenuAction.item("Widget Library…") { [weak self] in self?.showWidgetLibrary() })
        menu.addItem(NativeMenuAction.item("New App Folder…") { [weak self] in self?.itemDialogs.createFolder() })
        let widgets = NSMenu(title: "Add Widget")
        for kind in WidgetKind.allCases {
            widgets.addItem(NativeMenuAction.item(kind.title) { [weak self] in self?.add(.widget(kind)) })
        }
        let widgetItem = NSMenuItem(title: "Add Widget", action: nil, keyEquivalent: "")
        widgetItem.submenu = widgets
        menu.addItem(widgetItem)
        menu.addItem(NativeMenuAction.item("Add Applications…") { [weak self] in self?.itemDialogs.pickApplications() })
        menu.addItem(NativeMenuAction.item("Add File or Folder…") { [weak self] in self?.itemDialogs.pickFiles() })
        menu.addItem(NativeMenuAction.item("Add Link…") { [weak self] in self?.itemDialogs.addLink() })
        menu.addItem(NativeMenuAction.item("Add Spacer") { [weak self] in self?.add(DockItem(kind: .spacer, title: "Spacer", symbol: "line.3.vertical")) })
        menu.addItem(.separator())
        menu.addItem(NativeMenuAction.item("Edit Dock…") { [weak self] in guard let self else { return }; application?.editDock(profileID) })
        menu.addItem(NativeMenuAction.item("New Dock…") { [weak self] in self?.application?.newDock() })
        menu.addItem(NativeMenuAction.item("Hide This Dock") { [weak self] in guard let self else { return }; application?.hideDock(profileID) })
        return menu
    }

    func open(_ original: DockItem) {
        magnificationExit?.invalidate(); magnificationExit = nil
        lastPointer = nil
        guard let item = profile?.items.flatMap(\.containedItems).first(where: { $0.id == original.id }) ?? (NativeApplications.isRunning(original) ? original : nil) else { return }
        switch item.kind {
        case .folder:
            guard editor?.close() != false else { return }
            if let folderController, folderController.isShown {
                if folderController.folderID == item.id { folderController.close(); return }
                // Finish the previous popover's close callback before the new
                // one claims interaction, so its dismissal cannot hide the dock.
                folderController.close(animated: false)
            }
            guard let anchor = itemViews.first(where: { $0.item.id == item.id }) else { return }
            folderController = NativeFolderController(folderID: item.id, dock: self)
            let target = magnification?.popoverAnchor(for: item.id)
            folderController?.show(relativeTo: target?.view ?? anchor, rect: target?.rect)
        case .application:
            guard let address = item.url, let url = URL(string: address) else { return }
            // The system Dock bounces an icon until its app finishes launching.
            // An app that is already running just comes forward.
            let tile = itemViews.first { $0.item.id == item.id }
            if !NativeApplications.isRunning(item) { tile?.beginLaunchBounce() }
            // Launch Services sends the normal reopen request to a running app.
            // Activating its process alone leaves Finder with no window to show.
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] app, error in
                Task { @MainActor in
                    if let error {
                        tile?.endLaunchBounce()
                        (NSApplication.shared.delegate as? MacApplication)?.report(error.localizedDescription)
                        return
                    }
                    // A dock click should also bring forward this app's windows
                    // on other displays, not just its last key window.
                    app?.activate(options: .activateAllWindows)
                    if let app, let tile { self?.trackLaunch(of: app, for: tile) } else { tile?.endLaunchBounce() }
                }
            }
        case .link:
            if let address = item.url, let url = DockArchive.allowedURL(address), !NSWorkspace.shared.open(url) { application?.report("No application could open this link.") }
        case .trash:
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
        case .file:
            do {
                guard let bookmark = item.bookmark else { return }
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard NSWorkspace.shared.open(url) else { throw CocoaError(.fileNoSuchFile) }
            } catch { application?.report(error.localizedDescription) }
        case .widget:
            if editor?.isShown == true && editor?.itemID == item.id { editor?.close(); return }
            guard editor?.close() != false else { return }
            folderController?.close()
            reveal(animated: false)
            root.layoutSubtreeIfNeeded()
            guard let anchor = itemViews.first(where: { $0.item.id == item.id }) else { return }
            anchor.scrollToVisible(anchor.bounds)
            editor = NativeWidgetEditor(itemID: item.id, dock: self)
            let target = magnification?.popoverAnchor(for: item.id)
            editor?.show(relativeTo: target?.view ?? anchor, rect: target?.rect)
        case .spacer: break
        }
    }

    private func trackLaunch(of app: NSRunningApplication, for tile: NativeDockItemView) {
        let id = tile.item.id
        guard tile.isLaunching else { return }
        let finish: () -> Void = { [weak self, weak tile] in
            tile?.endLaunchBounce()
            self?.launchObservers[id] = nil
            self?.launchTimers[id]?.invalidate()
            self?.launchTimers[id] = nil
        }
        if app.isFinishedLaunching || app.isTerminated { finish(); return }
        launchObservers[id] = app.observe(\.isFinishedLaunching, options: [.new]) { app, _ in
            guard app.isFinishedLaunching else { return }
            Task { @MainActor in finish() }
        }
        // A launch that never reports completion must not bounce forever.
        launchTimers[id]?.invalidate()
        launchTimers[id] = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { _ in
            MainActor.assumeIsolated { finish() }
        }
    }

    func openNewWindow(_ item: DockItem) {
        folderController?.close()
        NativeApplicationWindows.openNewWindow(item) { [weak self] error in
            if let error { self?.application?.report(error) }
        }
    }

    func beginDrag(_ view: NativeDockItemView) {
        interacting = true
        reveal()
        draggedView = view
        previewUntil = .distantPast
        magnificationExit?.invalidate(); magnificationExit = nil
        hoverLabel.hide()
        // The overlay retains mouse capture until release, but the resting row
        // supplies stable drop targets and the drag preview.
        magnification?.showDragSurface()
        root.alphaValue = 1
        itemViews.forEach { $0.alphaValue = 1 }
        dragLayout = [:]
        dropFrame = nil
        landingPreview?.removeFromSuperview(); landingPreview = nil
        // Render the layers, not cacheDisplay: icons are layer contents that a
        // display cache does not capture.
        let preview = NSImageView(image: view.snapshot())
        preview.imageScaling = .scaleAxesIndependently
        preview.frame = view.frame
        preview.wantsLayer = true
        dockContent.addSubview(preview, positioned: .above, relativeTo: nil)
        dragImage = preview
        liftDragPreview(preview)
        // The lifted icon travels with the pointer while its slot closes and a
        // gap opens under it, like the system Dock. The tile itself stays put.
        view.alphaValue = 0
    }

    /// The picked-up item grows slightly and casts a soft shadow, so it reads
    /// as lifted off the shelf rather than sliding along it.
    private func liftDragPreview(_ preview: NSView) {
        guard let layer = preview.layer else { return }
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: -3)
        guard !NativeMotion.reducesMotion else { return }
        preview.frame = preview.frame.insetBy(dx: -preview.frame.width * 0.04, dy: -preview.frame.height * 0.04)
        // AppKit anchors view layers at a corner; scale about the centre instead.
        let center = CGPoint(x: preview.bounds.midX, y: preview.bounds.midY)
        let start = CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-center.x, -center.y, 0),
                                                            CATransform3DMakeScale(0.92, 0.92, 1)),
                                        CATransform3DMakeTranslation(center.x, center.y, 0))
        let grow = NativeMotion.spring("transform", duration: 0.25, bounce: 0.2)
        grow.fromValue = NSValue(caTransform3D: start)
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        layer.add(grow, forKey: "dockLift")
    }

    private func applyDragLayout(_ views: [NativeDockItemView], frames: [NSRect]) {
        var changed = false
        for (view, frame) in zip(views, frames) where dragLayout[ObjectIdentifier(view)] != frame {
            dragLayout[ObjectIdentifier(view)] = frame
            changed = true
        }
        guard changed else { return }
        NativeMotion.animate(0.2) {
            for (view, frame) in zip(views, frames) where view.frame != frame { view.animator().frame = frame }
        }
    }

    func updateDrag(at windowPoint: NSPoint) {
        guard let draggedView, let profile else { return }
        let point = dockContent.convert(windowPoint, from: nil)
        if let dragImage { dragImage.setFrameOrigin(NSPoint(x: point.x - dragImage.frame.width / 2, y: point.y - dragImage.frame.height / 2)) }
        itemViews.forEach { $0.showGrouping(false) }
        dropTarget = nil
        groupTarget = nil
        dropFrame = nil
        let vertical = draggedView.vertical
        let size = draggedView.iconSize
        let thickness = vertical ? contentSize.width : contentSize.height
        let others = itemViews.filter { $0 !== draggedView }
        let lengths = others.map { Self.length(of: $0.item, iconSize: size, vertical: vertical) }
        let closed = Self.rowFrames(lengths: lengths, thickness: thickness, vertical: vertical)
        let draggedLength = Self.length(of: draggedView.item, iconSize: size, vertical: vertical)
        func axis(_ rect: NSRect) -> CGFloat { vertical ? rect.midY : rect.midX }
        let coordinate = vertical ? point.y : point.x
        guard root.bounds.contains(root.convert(windowPoint, from: nil)), !others.isEmpty || profile.items.isEmpty else {
            groupCandidate = nil; groupTimer?.invalidate()
            applyDragLayout(others, frames: closed)
            return
        }
        let pinned = others.indices.filter { index in profile.items.contains { $0.id == others[index].item.id } }
        if draggedView.item.kind == .application,
           let nearest = pinned.min(by: { abs(axis(closed[$0]) - coordinate) < abs(axis(closed[$1]) - coordinate) }),
           [.application, .folder].contains(others[nearest].item.kind) {
            let target = others[nearest]
            let visible = dragLayout[ObjectIdentifier(target)] ?? target.frame
            if visible.insetBy(dx: visible.width * 0.25, dy: visible.height * 0.2).contains(point) {
                if groupCandidate?.0 != target.item.id {
                    groupCandidate = (target.item.id, Date())
                    groupTimer?.invalidate()
                    groupTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                        MainActor.assumeIsolated {
                            guard let self, let window = self.window else { return }
                            self.updateDrag(at: window.convertPoint(fromScreen: NSEvent.mouseLocation))
                        }
                    }
                }
                if target.item.kind == .folder || Date().timeIntervalSince(groupCandidate!.1) >= 0.45 {
                    groupTarget = target.item.id
                    target.showGrouping(true)
                    applyDragLayout(others, frames: closed)
                    return
                }
            } else {
                groupCandidate = nil
                groupTimer?.invalidate()
            }
        } else {
            groupCandidate = nil
            groupTimer?.invalidate()
        }
        let insertion = closed.firstIndex { axis($0) > coordinate } ?? others.count
        let gapOffset = insertion < closed.count ? (vertical ? closed[insertion].minY : closed[insertion].minX)
            : (closed.last.map { (vertical ? $0.maxY : $0.maxX) + 3 } ?? 8)
        dropFrame = vertical ? NSRect(x: 6, y: gapOffset, width: thickness - 12, height: draggedLength)
            : NSRect(x: gapOffset, y: 6, width: draggedLength, height: thickness - 12)
        applyDragLayout(others, frames: Self.rowFrames(lengths: lengths, thickness: thickness, vertical: vertical, gap: (insertion, draggedLength)))
        // The store orders relative to pinned items only. Running apps that are
        // not kept in the dock sit between them, so choose the nearer neighbor.
        let next = pinned.first { $0 >= insertion }
        let previous = pinned.last { $0 < insertion }
        switch (previous, next) {
        case let (previous?, next?):
            dropTarget = insertion - 1 - previous <= next - insertion ? (others[previous].item.id, true) : (others[next].item.id, false)
        case let (previous?, nil): dropTarget = (others[previous].item.id, true)
        case let (nil, next?): dropTarget = (others[next].item.id, false)
        default: dropTarget = nil
        }
    }

    func finishDrag(at windowPoint: NSPoint) {
        updateDrag(at: windowPoint)
        let source = draggedView?.item
        let destination = dropTarget
        let grouping = groupTarget
        let dragged = draggedView
        let landing = dropFrame
        let groupingFrame = grouping.flatMap { id in itemViews.first { $0.item.id == id } }.map { dragLayout[ObjectIdentifier($0)] ?? $0.frame }
        groupTimer?.invalidate()
        groupCandidate = nil
        groupTarget = nil
        let preview = dragImage
        dragImage = nil
        draggedView = nil
        dropTarget = nil
        dropFrame = nil
        dragLayout = [:]
        itemViews.forEach { $0.showGrouping(false) }
        interacting = false
        endMagnification()
        lastPointer = nil
        var changed = false
        do {
            if let source, let grouping {
                try store.drop(source, relativeTo: grouping, placement: .group, in: profileID)
                changed = true
            } else if let source, let destination {
                try store.drop(source, relativeTo: destination.0, placement: destination.1 ? .after : .before, in: profileID)
                changed = true
            }
        } catch { application?.report(error.localizedDescription) }
        // The lifted icon settles into its slot, or shrinks into the folder it
        // joined. An abandoned drag returns the row to its resting layout.
        if let preview, !NativeMotion.reducesMotion, dragged?.superview != nil {
            landingPreview = preview
            let target = grouping != nil ? groupingFrame : (changed ? landing : dragged?.frame)
            NativeMotion.animate(0.22) {
                if let target {
                    preview.animator().frame = grouping != nil ? target.insetBy(dx: target.width * 0.3, dy: target.height * 0.3) : target
                }
                if grouping != nil || target == nil { preview.animator().alphaValue = 0 }
            } completion: { [weak self] in
                preview.removeFromSuperview()
                if self?.landingPreview === preview { self?.landingPreview = nil }
                dragged?.alphaValue = 1
            }
        } else {
            preview?.removeFromSuperview()
            dragged?.alphaValue = 1
        }
        if !changed { reload() }
        scheduleHide()
    }

    func showWidgetLibrary() {
        widgetLibrary = NativeWidgetLibrary(profileName: profile?.name ?? "Dock") { [weak self] kind in
            guard let self else { return }
            let item = DockItem.widget(kind)
            add(item)
            if [.webValue, .custom, .note, .worldClock, .countdown].contains(kind) { open(item) }
        }
        widgetLibrary?.showWindow(nil)
        widgetLibrary?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var itemDialogs: NativeItemDialogs {
        NativeItemDialogs(profileID: profileID, store: store, application: application)
    }

    func add(_ item: DockItem) {
        do { try store.add(item, to: profileID) } catch { application?.report(error.localizedDescription) }
    }
    func remove(_ id: UUID) {
        guard var profile else { return }
        if !NativeMotion.reducesMotion, let tile = itemViews.first(where: { $0.item.id == id }), let window = tile.window {
            let rect = window.convertToScreen(tile.convert(tile.bounds, to: nil))
            let side = min(rect.width, rect.height)
            NSAnimationEffect.poof.show(centeredAt: NSPoint(x: rect.midX, y: rect.midY), size: NSSize(width: side, height: side))
        }
        profile.items.removeAll { $0.id == id }
        do { try store.update(profile) } catch { application?.report(error.localizedDescription) }
    }


}

final class NativeMenuAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
    static func item(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
        let handler = NativeMenuAction(action)
        let item = NSMenuItem(title: title, action: #selector(invoke), keyEquivalent: "")
        item.target = handler
        item.representedObject = handler
        return item
    }
}

class FlippedNativeView: NSView { override var isFlipped: Bool { true } }

final class DockGlassRoot: NSView {
    weak var controller: NativeDockController?
    let scroll = NSScrollView()
    private let material: NSView
    private var document: NSView?
    private var tracking: NSTrackingArea?
    private var colorObserver: NSObjectProtocol?
    var autoHide = false {
        didSet {
            if autoHide { controller?.scheduleHide() } else { controller?.reveal() }
        }
    }
    /// While magnified, the shelf widens around the row. The row itself keeps
    /// its resting origin so item coordinates stay valid.
    var materialFrameOverride: NSRect? {
        didSet {
            guard materialFrameOverride != oldValue else { return }
            // Only the material moves; the row keeps its layout.
            material.frame = materialFrameOverride ?? bounds
        }
    }

    static func configure(_ material: NSView, appearance: DockAppearance, cornerRadius: CGFloat? = nil) {
        let tint = NativeDockStyle.tint(named: appearance.tintColor, strength: appearance.glassTint)
        if #available(macOS 26.0, *), let glass = material as? NSGlassEffectView {
            glass.style = appearance.glassStyle == "Clear" ? .clear : .regular
            glass.tintColor = tint
            if let cornerRadius { glass.cornerRadius = cornerRadius }
        } else if let effect = material as? NSVisualEffectView {
            // Materials that follow the desktop appearance, like the system
            // Dock before Liquid Glass. HUD material stays dark on a light desktop.
            effect.material = appearance.glassStyle == "Clear" ? .underWindowBackground : .popover
            var color = tint?.cgColor
            effect.effectiveAppearance.performAsCurrentDrawingAppearance { color = tint?.cgColor }
            effect.layer?.backgroundColor = color
            if let cornerRadius { effect.layer?.cornerRadius = cornerRadius }
            Self.updateEdge(of: effect)
        }
    }

    /// A hairline highlight separates the fallback shelf from the desktop:
    /// a light rim in dark mode and a soft edge in light mode, like glass.
    static func updateEdge(of effect: NSVisualEffectView) {
        let dark = effect.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        effect.layer?.borderColor = (dark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.1)).cgColor
        effect.layer?.borderWidth = 1 / (effect.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
    }

    private var appearanceSettings: DockAppearance?
    func configure(_ appearance: DockAppearance, cornerRadius: CGFloat) {
        appearanceSettings = appearance
        Self.configure(material, appearance: appearance, cornerRadius: cornerRadius)
    }

    static func makeMaterial(containing content: NSView, cornerRadius: CGFloat = 18) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = cornerRadius
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            updateEdge(of: effect)
            effect.addSubview(content)
            content.autoresizingMask = [.width, .height]
            return effect
        }
    }

    override init(frame frameRect: NSRect) {
        material = Self.makeMaterial(containing: NSView())
        super.init(frame: frameRect)
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        addSubview(material)
        addSubview(scroll)
        clipsToBounds = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        material.autoresizingMask = [.width, .height]
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        // An Accent tint follows the system accent colour when it changes.
        colorObserver = NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let settings = self.appearanceSettings else { return }
                Self.configure(self.material, appearance: settings)
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { if let colorObserver { NotificationCenter.default.removeObserver(colorObserver) } }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // The hairline edge is one device pixel on every display.
        if let effect = material as? NSVisualEffectView { Self.updateEdge(of: effect) }
    }
    func setDocumentView(_ view: NSView) {
        document = view
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Accent tints and edges resolve per appearance.
        if let appearanceSettings { Self.configure(material, appearance: appearanceSettings) }
        else if let effect = material as? NSVisualEffectView { Self.updateEdge(of: effect) }
    }

    override func layout() {
        super.layout()
        material.frame = materialFrameOverride ?? bounds
        scroll.frame = bounds
        guard let document else { return }
        let overflows = document.frame.width > bounds.width + 0.5 || document.frame.height > bounds.height + 0.5
        scroll.hasHorizontalScroller = document.frame.width > bounds.width + 0.5
        scroll.hasVerticalScroller = document.frame.height > bounds.height + 0.5
        scroll.isHidden = !overflows
        if overflows {
            if scroll.documentView !== document { scroll.documentView = document }
        } else {
            // The glass's mask and NSClipView both clip lifted icons. A row that
            // fits lives above the shelf from the start, not in either container.
            if scroll.documentView === document { scroll.documentView = nil }
            if document.superview !== self { addSubview(document) }
            document.setFrameOrigin(.zero)
            document.clipsToBounds = false
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { controller?.updatePointer() }
    override func mouseMoved(with event: NSEvent) { controller?.updatePointer() }
    override func mouseExited(with event: NSEvent) { controller?.updatePointer() }
    override func menu(for event: NSEvent) -> NSMenu? { controller?.menu(for: nil) }
}
#endif
