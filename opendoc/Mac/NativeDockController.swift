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
    private var folderController: NativeFolderController?
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
            MainActor.assumeIsolated { self?.positionPanel() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.hidden, self.window?.isVisible == true else { return }
                let now = Date()
                self.itemViews.forEach { $0.refreshIfNeeded(at: now) }
                self.magnification?.refreshWidgets()
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
        root.configure(profile.appearance)
        let vertical = profile.appearance.position != "Bottom"
        let size = CGFloat(profile.appearance.size)
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
        if popupOpen, magnification != nil, displayed.map(\.id) == itemViews.map({ $0.item.id }),
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
        let thickness = vertical ? max(84, size + 20) : size + 22
        var offset: CGFloat = 8
        for view in itemViews {
            let length: CGFloat
            switch view.item.kind {
            case .widget: length = vertical ? 76 : view.item.widget == .note ? 146 : view.item.widget == .calendar ? 122 : 126
            case .spacer: length = 12
            default: length = size + 7
            }
            let frame = vertical ? NSRect(x: 6, y: offset, width: thickness - 12, height: length) : NSRect(x: offset, y: 6, width: length, height: thickness - 12)
            if view.superview == nil {
                view.frame = frame
                dockContent.addSubview(view)
                view.alphaValue = 0
                NativeMotion.animate(0.18) { view.animator().alphaValue = 1 }
            } else if view.frame != frame {
                NativeMotion.animate(0.22) { view.animator().frame = frame }
            }
            offset += length + 3
        }
        settingsButton?.removeFromSuperview()
        let settings = NSButton(image: NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Dock settings")!, target: self, action: #selector(showMenu(_:)))
        settings.bezelStyle = .regularSquare
        settings.isBordered = false
        settings.contentTintColor = .secondaryLabelColor
        settings.toolTip = "Add widgets or edit this dock"
        settings.setAccessibilityLabel("Dock settings")
        settings.frame = vertical ? NSRect(x: 8, y: offset, width: thickness - 16, height: 25) : NSRect(x: offset + 3, y: 10, width: 25, height: thickness - 20)
        dockContent.addSubview(settings)
        let ordered: [NSView] = itemViews + [settings]
        dockContent.subviews = ordered
        settingsButton = settings
        offset += 38
        contentSize = vertical ? NSSize(width: thickness, height: offset) : NSSize(width: offset, height: thickness)
        dockContent.frame = NSRect(origin: .zero, size: contentSize)
        if root.scroll.documentView !== dockContent { root.scroll.documentView = dockContent }
        root.scroll.hasHorizontalScroller = false
        root.scroll.hasVerticalScroller = false
        positionPanel(animated: window?.isVisible == true && !hidden)
        root.autoHide = profile.appearance.autoHide
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
        root.frame = NSRect(origin: .zero, size: size)
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
        if draggedView != nil || magnification?.menuIsOpen == true || popupOpen { return }
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
                    MainActor.assumeIsolated { self?.endMagnification() }
                }
            }
            let local = dockContent.convert(window?.convertPoint(fromScreen: point) ?? .zero, from: nil)
            for tile in itemViews {
                let distance = tile.vertical ? abs(local.y - tile.frame.midY) : abs(local.x - tile.frame.midX)
                tile.setProximity(hoverActive ? max(0, 1 - distance / 85) : 0)
            }
        }
    }

    private func installMagnification() {
        // Overflow docks retain their scrollable row; a partial widget must not
        // be snapshotted outside the viewport into the magnification window.
        guard contentSize.width <= visibleFrame.width, let settingsButton else { return }
        let overlay = NativeDockMagnification(dock: self, tiles: itemViews, settings: settingsButton, bar: visibleFrame)
        // A failed overlay must never leave an empty glass bar behind.
        guard overlay.hasVisibleContent else { overlay.close(); return }
        magnification = overlay
        itemViews.forEach { $0.alphaValue = 0 }
        root.alphaValue = 0
    }

    func endMagnification() {
        previewUntil = .distantPast
        magnificationExit?.invalidate(); magnificationExit = nil
        magnification?.close(); magnification = nil
        root.alphaValue = 1
        itemViews.forEach { $0.alphaValue = 1; $0.setProximity(0) }
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
                self.endMagnification()
                self.hidden = true
                self.revealDwell.reset()
                NativeMotion.animate(0.24) { self.window?.animator().setFrame(self.hiddenFrame(on: screen), display: true) }
            }
        }
    }

    @objc private func showMenu(_ sender: NSButton) {
        let menu = menu(for: nil)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    func menuWillOpen(_ menu: NSMenu) { interacting = true; reveal(animated: false) }
    func menuDidClose(_ menu: NSMenu) { interacting = false; scheduleHide() }

    func menu(for item: DockItem?) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        if let item {
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
            if item.kind == .application, NativeApplications.isRunning(item) {
                menu.addItem(NativeMenuAction.item("Quit \(item.title)") {
                    NSWorkspace.shared.runningApplications.first { $0.bundleURL?.absoluteString == item.url }?.terminate()
                })
            }
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
            if folderController?.isShown == true { folderController?.close(); return }
            guard let anchor = itemViews.first(where: { $0.item.id == item.id }) else { return }
            folderController = NativeFolderController(folderID: item.id, dock: self)
            let target = magnification?.popoverAnchor(for: item.id)
            folderController?.show(relativeTo: target?.view ?? anchor, rect: target?.rect)
        case .application:
            guard let address = item.url, let url = URL(string: address) else { return }
            if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.standardizedFileURL.path == url.standardizedFileURL.path }) {
                running.activate(options: [.activateAllWindows])
            } else {
                NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                    if let error { Task { @MainActor in
                        (NSApplication.shared.delegate as? MacApplication)?.report(error.localizedDescription)
                    } }
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

    func beginDrag(_ view: NativeDockItemView) {
        interacting = true
        reveal()
        draggedView = view
        previewUntil = .distantPast
        magnificationExit?.invalidate(); magnificationExit = nil
        // The overlay retains mouse capture until release, but the resting row
        // supplies stable drop targets and the drag preview.
        magnification?.showDragSurface()
        root.alphaValue = 1
        itemViews.forEach { $0.alphaValue = 1; $0.setProximity(0) }
        let image = NSImage(size: view.bounds.size)
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            image.addRepresentation(bitmap)
        }
        let preview = NSImageView(image: image)
        preview.frame = view.frame
        preview.alphaValue = 0.9
        dockContent.addSubview(preview, positioned: .above, relativeTo: nil)
        dragImage = preview
        view.alphaValue = 0.3
    }

    func updateDrag(at windowPoint: NSPoint) {
        guard let draggedView else { return }
        let point = dockContent.convert(windowPoint, from: nil)
        dragImage?.setFrameOrigin(NSPoint(x: point.x - draggedView.bounds.midX, y: point.y - draggedView.bounds.midY))
        itemViews.forEach { $0.showInsertion(after: nil); $0.showGrouping(false) }
        dropTarget = nil
        groupTarget = nil
        guard root.bounds.contains(root.convert(windowPoint, from: nil)),
              let target = itemViews.filter({ candidate in
                  candidate !== draggedView && profile?.items.contains(where: { $0.id == candidate.item.id }) == true
              }).min(by: { first, second in
                  draggedView.vertical ? abs(first.frame.midY - point.y) < abs(second.frame.midY - point.y)
                      : abs(first.frame.midX - point.x) < abs(second.frame.midX - point.x)
              }) else {
            groupCandidate = nil; groupTimer?.invalidate(); return
        }
        if draggedView.item.kind == .application,
           [.application, .folder].contains(target.item.kind),
           target.frame.insetBy(dx: target.frame.width * 0.25, dy: target.frame.height * 0.2).contains(point) {
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
                return
            }
        } else {
            groupCandidate = nil
            groupTimer?.invalidate()
        }
        let after = target.vertical ? point.y > target.frame.midY : point.x > target.frame.midX
        target.showInsertion(after: after)
        dropTarget = (target.item.id, after)
    }

    func finishDrag(at windowPoint: NSPoint) {
        updateDrag(at: windowPoint)
        let source = draggedView?.item
        let destination = dropTarget
        let grouping = groupTarget
        groupTimer?.invalidate()
        groupCandidate = nil
        groupTarget = nil
        dragImage?.removeFromSuperview()
        dragImage = nil
        draggedView?.alphaValue = 1
        draggedView = nil
        dropTarget = nil
        itemViews.forEach { $0.showInsertion(after: nil); $0.showGrouping(false) }
        interacting = false
        endMagnification()
        lastPointer = nil
        do {
            if let source, let grouping {
                try store.drop(source, relativeTo: grouping, placement: .group, in: profileID)
            } else if let source, let destination {
                try store.drop(source, relativeTo: destination.0, placement: destination.1 ? .after : .before, in: profileID)
            }
        } catch { application?.report(error.localizedDescription) }
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
    private var tracking: NSTrackingArea?
    var autoHide = false {
        didSet {
            if autoHide { controller?.scheduleHide() } else { controller?.reveal() }
        }
    }

    static func makeFolderMaterial(containing content: NSView) -> NSView {
        makeMaterial(containing: content, cornerRadius: 13)
    }

    static func configure(_ material: NSView, appearance: DockAppearance) {
        if #available(macOS 26.0, *), let glass = material as? NSGlassEffectView {
            glass.style = appearance.glassStyle == "Clear" ? .clear : .regular
            glass.tintColor = appearance.glassTint == 0 ? nil : NSColor.black.withAlphaComponent(appearance.glassTint * 0.6)
        } else if let effect = material as? NSVisualEffectView {
            effect.material = appearance.glassStyle == "Clear" ? .underWindowBackground : .hudWindow
            effect.layer?.backgroundColor = NSColor.black.withAlphaComponent(appearance.glassTint * 0.6).cgColor
        }
    }

    func configure(_ appearance: DockAppearance) { Self.configure(material, appearance: appearance) }

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
            effect.layer?.masksToBounds = true
            effect.addSubview(content)
            content.autoresizingMask = [.width, .height]
            return effect
        }
    }

    override init(frame frameRect: NSRect) {
        material = Self.makeMaterial(containing: scroll)
        super.init(frame: frameRect)
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        addSubview(material)
        material.autoresizingMask = [.width, .height]
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layout() {
        super.layout()
        material.frame = bounds
        scroll.frame = material.bounds
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
