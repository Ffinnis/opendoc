#if os(macOS)
import AppKit
import UniformTypeIdentifiers

final class NativeFolderController: NSViewController, NSPopoverDelegate, NSTextFieldDelegate, NSMenuDelegate {
    let folderID: UUID
    private weak var dock: NativeDockController?
    private let popover = NSPopover()
    private weak var firstAppButton: NSButton?
    private var observer: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appButtons: [FolderAppButton] = []
    private var contextMenuOpen = false
    private var renderedFolder: Data?
    var isShown: Bool { popover.isShown }
    private var folder: DockItem? { dock?.profile?.items.first { $0.id == folderID } }

    init(folderID: UUID, dock: NativeDockController) {
        self.folderID = folderID
        self.dock = dock
        super.init(nibName: nil, bundle: nil)
        popover.contentViewController = self
        popover.behavior = .transient
        popover.delegate = self
        observer = NotificationCenter.default.addObserver(forName: DockStore.changed, object: dock.store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.folder == nil { self.popover.close() } else { self.render() }
            }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appButtons.forEach { $0.needsDisplay = true } }
            })
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
    override func loadView() { view = FlippedNativeView(); render() }

    func show(relativeTo anchor: NSView, rect: NSRect? = nil) {
        if popover.isShown { popover.performClose(nil); return }
        dock?.interacting = true
        dock?.reveal(animated: false)
        popover.animates = !NativeMotion.reducesMotion
        let edge: NSRectEdge = dock?.profile?.appearance.position == "Left" ? .maxX : dock?.profile?.appearance.position == "Right" ? .minX : .maxY
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: rect ?? anchor.bounds, of: anchor, preferredEdge: edge)
        view.window?.makeKeyAndOrderFront(nil)
        if let firstAppButton { view.window?.makeFirstResponder(firstAppButton) }
    }
    func popoverShouldClose(_ popover: NSPopover) -> Bool { !contextMenuOpen }
    func menuWillOpen(_ menu: NSMenu) { contextMenuOpen = true }
    func menuDidClose(_ menu: NSMenu) { contextMenuOpen = false }
    func close(animated: Bool = true) {
        popover.animates = animated && !NativeMotion.reducesMotion
        popover.performClose(nil)
    }
    func popoverDidClose(_ notification: Notification) {
        dock?.interacting = false; dock?.scheduleHide()
        popover.contentViewController = nil
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
    }

    private func render() {
        guard isViewLoaded, let folder else { return }
        // Widget updates elsewhere in the dock must not recreate buttons under
        // the pointer or discard the folder's keyboard focus and rename draft.
        let snapshot = try? JSONEncoder().encode(folder)
        guard snapshot != renderedFolder else { return }
        renderedFolder = snapshot
        view.subviews.forEach { $0.removeFromSuperview() }
        let children = folder.children ?? []
        let columns = 2
        let rows = max(1, (children.count + columns - 1) / columns)
        let inset: CGFloat = 24
        let width: CGFloat = 280
        let gridWidth = width - inset * 2
        let cellWidth = gridWidth / CGFloat(columns)
        let rowHeight: CGFloat = 102
        let gridHeight = CGFloat(rows) * rowHeight
        let visibleHeight = min(rowHeight * 4, gridHeight)
        let gridTop: CGFloat = 60
        let footerTop = gridTop + visibleHeight + 12
        let size = NSSize(width: width, height: footerTop + 60)
        view.setFrameSize(size)
        preferredContentSize = size
        popover.contentSize = size
        let title = NSTextField(string: folder.title)
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.isBezeled = false; title.drawsBackground = false; title.delegate = self
        title.frame = NSRect(x: inset - 2, y: 20, width: gridWidth + 4, height: 24)
        title.lineBreakMode = .byTruncatingTail
        title.toolTip = "Click to rename this folder"
        title.setAccessibilityLabel("Folder name")
        view.addSubview(title)
        let scroll = NSScrollView(frame: NSRect(x: inset, y: gridTop, width: gridWidth, height: visibleHeight))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = gridHeight > visibleHeight
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        let grid = FlippedNativeView(frame: NSRect(x: 0, y: 0, width: gridWidth, height: gridHeight))
        scroll.documentView = grid
        view.addSubview(scroll)
        if children.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: "Add applications to this folder, or drag an app onto it in the dock.")
            empty.textColor = .secondaryLabelColor
            empty.alignment = .center
            empty.font = .systemFont(ofSize: 12)
            empty.frame = NSRect(x: 8, y: 20, width: gridWidth - 16, height: 54)
            grid.addSubview(empty)
        }
        firstAppButton = nil
        appButtons = []
        for (index, item) in children.enumerated() {
            let x = CGFloat(index % columns) * cellWidth
            let y = CGFloat(index / columns) * rowHeight
            let button = FolderAppButton(item) { [weak self] in
                self?.popover.performClose(nil)
                self?.dock?.open(item)
            }
            appButtons.append(button)
            if index == 0 { firstAppButton = button }
            button.image = NativeApplications.icon(for: item)
            button.imageScaling = .scaleProportionallyUpOrDown
            button.isBordered = false
            button.frame = NSRect(x: x + 2, y: y, width: cellWidth - 4, height: rowHeight - 4)
            let titleWidth = (item.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
            button.toolTip = titleWidth > button.bounds.width - 8 ? item.title : nil
            button.setAccessibilityLabel(item.title)
            let menu = NSMenu()
            menu.delegate = self
            menu.addItem(NativeMenuAction.item("Move to Dock") { [weak self] in
                guard let self, let dock else { return }
                do { try dock.store.moveOutOfFolder(item.id, folderID: folderID, in: dock.profileID) }
                catch { dock.application?.report(error.localizedDescription) }
            })
            menu.addItem(NativeMenuAction.item("Remove from Folder") { [weak self] in
                self?.edit { $0.children?.removeAll { $0.id == item.id } }
            })
            button.menu = menu
            grid.addSubview(button)
        }
        let separator = NSBox(frame: NSRect(x: inset, y: footerTop, width: gridWidth, height: 1))
        separator.boxType = .separator
        view.addSubview(separator)
        let add = NativeButton("Add Applications…") { [weak self] in self?.pickApplications() }
        add.controlSize = .regular
        add.font = .systemFont(ofSize: 13)
        add.frame = NSRect(x: inset, y: footerTop + 13, width: 150, height: 28)
        view.addSubview(add)
        let count = NSTextField(labelWithString: children.count == 1 ? "1 app" : "\(children.count) apps")
        count.textColor = .secondaryLabelColor; count.font = .systemFont(ofSize: 11)
        count.alignment = .right
        count.frame = NSRect(x: width - inset - 64, y: footerTop + 19, width: 64, height: 18)
        view.addSubview(count)
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { field.stringValue = folder?.title ?? "Folder"; return }
        edit { $0.title = name }
    }
    private func edit(_ change: (inout DockItem) -> Void) {
        guard var folder, let dock else { return }
        change(&folder)
        do { try dock.store.updateItem(folder) } catch { dock.application?.report(error.localizedDescription) }
    }
    private func pickApplications() {
        let picker = NSOpenPanel()
        picker.title = "Add Applications to Folder"
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.allowedContentTypes = [.applicationBundle]
        picker.allowsMultipleSelection = true
        picker.begin { [weak self] response in
            guard response == .OK else { return }
            guard let self, let dock else { return }
            do { try dock.store.addApplications(picker.urls.map { NativeApplications.item(for: $0) }, into: folderID, in: dock.profileID) }
            catch { dock.application?.report(error.localizedDescription) }
        }
    }
}

/// A single native button owns the entire tile, including its label and padding.
/// Hover feedback changes color only, so app targets never move beneath the mouse.
private final class FolderAppButton: NSButton {
    private let handler: () -> Void
    private let item: DockItem
    private var tracking: NSTrackingArea?
    private var hovered = false

    init(_ item: DockItem, handler: @escaping () -> Void) {
        self.item = item
        self.handler = handler
        super.init(frame: .zero)
        self.title = item.title
        isBordered = false
        target = self
        action = #selector(invoke)
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func invoke() { handler() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { true }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        needsDisplay = true
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        needsDisplay = true
        return accepted
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        if let window { hovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
        needsDisplay = true
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let focused = window?.firstResponder === self
        if hovered || isHighlighted || focused {
            NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.18 : focused ? 0.12 : 0.07).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10).fill()
        }
        image?.draw(in: NSRect(x: (bounds.width - 56) / 2, y: 2, width: 56, height: 56),
                    from: .zero, operation: .sourceOver, fraction: isHighlighted ? 0.75 : 1,
                    respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        if NativeApplications.isRunning(item) {
            NSColor.secondaryLabelColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.midX - 1.5, y: 62, width: 3, height: 3)).fill()
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: NSRect(x: 4, y: 73, width: bounds.width - 8, height: 18),
            withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
                             .paragraphStyle: paragraph])
    }
}
#endif
