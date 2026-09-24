#if os(macOS)
import AppKit
import UniformTypeIdentifiers

final class NativePreferencesController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSToolbarDelegate, NSTextFieldDelegate, NSToolbarItemValidation {
    let store: DockStore
    weak var application: MacApplication?
    private let profiles = NSTableView()
    private let items = NSTableView()
    private let titleField = NSTextField(string: "")
    private let visible = NSButton(checkboxWithTitle: "Show this dock on desktop", target: nil, action: nil)
    private let replace = NSButton(checkboxWithTitle: "Replace Apple’s Dock while Open Doc is running", target: nil, action: nil)
    private let position = NSSegmentedControl(labels: ["Left", "Bottom", "Right"], trackingMode: .selectOne, target: nil, action: nil)
    private let material = NSPopUpButton()
    private let glassStyle = NSSegmentedControl(labels: ["Clear", "Regular"], trackingMode: .selectOne, target: nil, action: nil)
    private let tintSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let tintLabel = NSTextField(labelWithString: "None")
    private let tintPicker = NativeTintPicker()
    private let preview = NativeDockPreview()
    private let sizeSlider = NSSlider(value: 44, minValue: 36, maxValue: 88, target: nil, action: nil)
    private let sizeLabel = NSTextField(labelWithString: "44 pt")
    private let autoHide = NSButton(checkboxWithTitle: "Automatically hide and show this dock", target: nil, action: nil)
    private let detail = NSStackView()
    private let options = NSStackView()
    private let optionsScroll = NSScrollView()
    private let tabs = NSSegmentedControl(labels: ["Items", "Appearance"], trackingMode: .selectOne, target: nil, action: nil)
    private let itemScroll = NSScrollView()
    private let footer = NSTextField(wrappingLabelWithString: "")
    private var updating = false
    private var widgetLibrary: NativeWidgetLibrary?

    init(store: DockStore, application: MacApplication) {
        self.store = store; self.application = application
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 590), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Open Doc"
        window.minSize = NSSize(width: 700, height: 480)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("OpenDocNativeSettings")
        window.center()
        super.init(window: window)
        let toolbar = NSToolbar(identifier: "OpenDocSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        buildContent()
        refresh()
    }
    override var undoManager: UndoManager? { store.undoManager }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private func buildContent() {
        let split = NSSplitViewController()
        let sidebar = NSViewController()
        let sidebarScroll = NSScrollView()
        sidebarScroll.drawsBackground = false
        sidebarScroll.hasVerticalScroller = true
        profiles.headerView = nil
        profiles.style = .sourceList
        profiles.rowHeight = 32
        profiles.dataSource = self; profiles.delegate = self
        profiles.addTableColumn(NSTableColumn(identifier: .init("profiles")))
        profiles.setAccessibilityIdentifier("dock-profiles")
        sidebarScroll.documentView = profiles
        sidebar.view = sidebarScroll
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 170
        sidebarItem.maximumThickness = 260
        split.addSplitViewItem(sidebarItem)
        let editor = NSViewController()
        editor.view = NSView()
        detail.orientation = .vertical
        detail.alignment = .leading
        detail.spacing = 16
        detail.translatesAutoresizingMaskIntoConstraints = false
        editor.view.addSubview(detail)
        NSLayoutConstraint.activate([
            detail.leadingAnchor.constraint(equalTo: editor.view.leadingAnchor, constant: 22), detail.trailingAnchor.constraint(equalTo: editor.view.trailingAnchor, constant: -22),
            detail.topAnchor.constraint(equalTo: editor.view.topAnchor, constant: 22), detail.bottomAnchor.constraint(equalTo: editor.view.bottomAnchor, constant: -18)
        ])
        titleField.font = .systemFont(ofSize: 17, weight: .semibold)
        titleField.isBezeled = false; titleField.drawsBackground = false
        titleField.delegate = self
        titleField.setAccessibilityLabel("Dock name")
        titleField.setAccessibilityIdentifier("dock-name")
        detail.addArrangedSubview(titleField)
        visible.target = self; visible.action = #selector(toggleVisible)
        detail.addArrangedSubview(visible)
        tabs.selectedSegment = 0; tabs.target = self; tabs.action = #selector(changeTab)
        detail.addArrangedSubview(tabs)
        let nameColumn = NSTableColumn(identifier: .init("item"))
        nameColumn.width = 320; nameColumn.minWidth = 200
        items.addTableColumn(nameColumn)
        let type = NSTableColumn(identifier: .init("kind")); type.width = 95; type.minWidth = 95; type.maxWidth = 95
        items.addTableColumn(type)
        items.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        items.allowsMultipleSelection = true
        items.headerView = nil; items.style = .inset
        items.rowHeight = 40; items.dataSource = self; items.delegate = self
        items.target = self; items.doubleAction = #selector(editSelected)
        items.registerForDraggedTypes([.string])
        items.setAccessibilityIdentifier("dock-items")
        itemScroll.documentView = items; itemScroll.hasVerticalScroller = true
        itemScroll.borderType = .bezelBorder
        detail.addArrangedSubview(itemScroll)
        itemScroll.widthAnchor.constraint(equalTo: detail.widthAnchor).isActive = true
        itemScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        options.orientation = .vertical; options.alignment = .leading; options.spacing = 14
        position.target = self; position.action = #selector(changeAppearance)
        position.setAccessibilityLabel("Dock position")
        material.addItems(withTitles: ["Automatic", "Light", "Dark"])
        material.target = self; material.action = #selector(changeAppearance)
        material.setAccessibilityLabel("Dock material")
        sizeSlider.target = self; sizeSlider.action = #selector(changeAppearance)
        sizeSlider.isContinuous = false
        sizeSlider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        sizeSlider.setAccessibilityLabel("Icon size")
        autoHide.target = self; autoHide.action = #selector(changeAppearance)
        glassStyle.target = self; glassStyle.action = #selector(changeAppearance)
        glassStyle.setAccessibilityLabel("Glass style")
        tintSlider.target = self; tintSlider.action = #selector(changeAppearance)
        tintSlider.isContinuous = false
        tintSlider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        tintSlider.setAccessibilityLabel("Glass tint strength")
        tintPicker.onChange = { [weak self] changed in
            guard let self else { return }
            // Picking a colour with no strength would change nothing visible,
            // including the colour that is already selected.
            if tintSlider.doubleValue == 0 { tintSlider.doubleValue = 0.35 }
            else if !changed { return }
            changeAppearance()
        }
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(equalToConstant: 104).isActive = true
        options.addArrangedSubview(preview)
        preview.widthAnchor.constraint(equalTo: options.widthAnchor).isActive = true
        let tint = NSStackView(views: [tintSlider, tintLabel]); tint.spacing = 10
        let magnify = NativeButton("Preview Magnification") { [weak self] in
            guard let self else { return }
            application?.previewMagnification(in: store.active.id)
        }
        let sizing = NSStackView(views: [sizeSlider, sizeLabel]); sizing.orientation = .horizontal; sizing.spacing = 10
        options.addArrangedSubview(section("Placement", [("Position", position), ("", autoHide)]))
        options.addArrangedSubview(section("Glass", [("Material", material), ("Style", glassStyle), ("Tint", tintPicker), ("Strength", tint)]))
        options.addArrangedSubview(section("Icons", [("Size", sizing), ("", magnify)]))
        // Scrolls in short windows instead of compressing the controls.
        let document = FlippedNativeView()
        options.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(options)
        document.translatesAutoresizingMaskIntoConstraints = false
        optionsScroll.documentView = document
        optionsScroll.drawsBackground = false
        optionsScroll.hasVerticalScroller = true
        optionsScroll.autohidesScrollers = true
        let clip = optionsScroll.contentView
        NSLayoutConstraint.activate([
            options.topAnchor.constraint(equalTo: document.topAnchor), options.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -8),
            options.leadingAnchor.constraint(equalTo: document.leadingAnchor), options.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -2),
            document.topAnchor.constraint(equalTo: clip.topAnchor), document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.widthAnchor.constraint(equalTo: clip.widthAnchor)
        ])
        detail.addArrangedSubview(optionsScroll)
        optionsScroll.widthAnchor.constraint(equalTo: detail.widthAnchor).isActive = true
        optionsScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        optionsScroll.isHidden = true
        footer.font = .systemFont(ofSize: 11); footer.textColor = .secondaryLabelColor
        detail.addArrangedSubview(footer)
        replace.target = self; replace.action = #selector(toggleReplacement)
        let restore = NSButton(title: "Restore Apple’s Dock", target: self, action: #selector(restoreSystemDock))
        restore.bezelStyle = .rounded
        detail.addArrangedSubview(replace)
        detail.addArrangedSubview(restore)
        split.addSplitViewItem(NSSplitViewItem(viewController: editor))
        window?.contentViewController = split
    }

    /// A titled group of right-aligned labels and controls, like System Settings.
    private func section(_ title: String, _ rows: [(String, NSView)]) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        let grid = NSGridView(views: rows.map { label, control in
            let field = NSTextField(labelWithString: label.isEmpty ? "" : label + ":")
            field.textColor = .secondaryLabelColor
            return [field, control]
        })
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 80
        grid.rowAlignment = .firstBaseline
        for index in 0..<grid.numberOfRows where rows[index].1 is NativeTintPicker || rows[index].1 is NSStackView {
            grid.row(at: index).rowAlignment = .none
            grid.cell(atColumnIndex: 0, rowIndex: index).yPlacement = .center
            grid.cell(atColumnIndex: 1, rowIndex: index).yPlacement = .center
        }
        let stack = NSStackView(views: [heading, grid])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        return stack
    }

    func refresh() {
        updating = true
        let selected = items.selectedRow
        profiles.reloadData()
        if let index = store.archive.profiles.firstIndex(where: { $0.id == store.active.id }) { profiles.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        titleField.stringValue = store.active.name
        visible.state = application?.isDockVisible(store.active.id) == true ? .on : .off
        replace.state = SystemDockSession.isActive ? .on : .off
        let appearance = store.active.appearance
        position.selectedSegment = ["Left", "Bottom", "Right"].firstIndex(of: appearance.position) ?? 1
        material.selectItem(at: ["Glass", "Light", "Dark"].firstIndex(of: appearance.material) ?? 0)
        glassStyle.selectedSegment = appearance.glassStyle == "Clear" ? 0 : 1
        tintSlider.doubleValue = appearance.glassTint
        tintLabel.stringValue = appearance.glassTint == 0 ? "None" : "\(Int(appearance.glassTint * 100))%"
        tintPicker.selected = appearance.tintColor
        // A hidden dock's data widgets stay idle in the preview; a visible dock
        // already fetches the same readings, so its preview shares them.
        preview.show(Array(store.active.items.filter { $0.kind != .spacer }.prefix(8)), appearance: appearance, iconSize: min(48, appearance.size),
                     live: application?.isDockVisible(store.active.id) == true)
        sizeSlider.doubleValue = appearance.size; sizeLabel.stringValue = "\(Int(appearance.size)) pt"
        autoHide.state = appearance.autoHide ? .on : .off
        items.reloadData()
        if store.active.items.indices.contains(selected) { items.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false) }
        footer.stringValue = "\(store.active.items.count) items. Select apps to group them. Double-click to edit a widget or open a folder."
        updating = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === profiles ? store.archive.profiles.count : store.active.items.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === profiles {
            let profile = store.archive.profiles[row]
            let cell = NSTableCellView()
            let image = NSImageView(image: NSImage(systemSymbolName: profile.symbol, accessibilityDescription: nil) ?? NSImage())
            let text = NSTextField(labelWithString: profile.name)
            let stack = NSStackView(views: [image, text]); stack.orientation = .horizontal; stack.spacing = 8
            stack.frame = NSRect(x: 8, y: 5, width: tableColumn?.width ?? 180, height: 22)
            cell.addSubview(stack); cell.textField = text; cell.imageView = image
            cell.setAccessibilityIdentifier("profile-\(profile.name)")
            return cell
        }
        let item = store.active.items[row]
        if tableColumn?.identifier.rawValue == "kind" {
            let cell = NSTableCellView()
            let text = NSTextField(labelWithString: item.kind == .widget ? "Widget" : item.kind.rawValue.capitalized)
            text.font = .systemFont(ofSize: 11); text.textColor = .secondaryLabelColor
            text.frame = NSRect(x: 4, y: 12, width: 87, height: 18)
            cell.addSubview(text); cell.textField = text
            return cell
        }
        let cell = NSTableCellView()
        let image = NSImageView(image: NativeApplications.icon(for: item))
        image.frame = NSRect(x: 6, y: 5, width: 30, height: 30)
        image.imageScaling = .scaleProportionallyUpOrDown
        let text = NSTextField(labelWithString: item.title)
        text.frame = NSRect(x: 46, y: 11, width: max(80, (tableColumn?.width ?? 250) - 55), height: 20)
        text.lineBreakMode = .byTruncatingTail
        text.autoresizingMask = [.width]
        cell.addSubview(image); cell.addSubview(text); cell.textField = text; cell.imageView = image
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        window?.toolbar?.validateVisibleItems()
        guard !updating, notification.object as? NSTableView === profiles,
              store.archive.profiles.indices.contains(profiles.selectedRow) else { return }
        let id = store.archive.profiles[profiles.selectedRow].id
        guard id != store.active.id else { return }
        do { try store.select(id) } catch { application?.report(error.localizedDescription) }
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as? NSTextField === titleField, !updating else { return }
        var profile = store.active
        let name = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { refresh(); return }
        profile.name = name
        save(profile)
    }

    @objc private func changeTab() {
        itemScroll.isHidden = tabs.selectedSegment != 0
        optionsScroll.isHidden = tabs.selectedSegment != 1
        footer.isHidden = tabs.selectedSegment != 0
    }
    @objc private func toggleVisible() {
        if visible.state == .on { application?.showDock(store.active.id) } else { application?.hideDock(store.active.id) }
        refresh()
    }
    @objc private func toggleReplacement() { application?.setReplacement(replace.state == .on); refresh() }
    @objc private func restoreSystemDock() { application?.setReplacement(false); refresh() }
    @objc private func changeAppearance() {
        guard !updating else { return }
        var profile = store.active
        profile.appearance.position = ["Left", "Bottom", "Right"][position.selectedSegment]
        profile.appearance.material = ["Glass", "Light", "Dark"][material.indexOfSelectedItem]
        profile.appearance.glassStyle = glassStyle.selectedSegment == 0 ? "Clear" : "Regular"
        profile.appearance.glassTint = tintSlider.doubleValue
        profile.appearance.tintColor = tintPicker.selected
        profile.appearance.size = sizeSlider.doubleValue.rounded()
        profile.appearance.autoHide = autoHide.state == .on
        save(profile)
    }
    private func save(_ profile: DockProfile) { do { try store.update(profile) } catch { application?.report(error.localizedDescription) } }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.toggleSidebar, .init("new"), .flexibleSpace, .init("add"), .init("widgets"), .init("group"), .init("remove"), .init("more")] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier.rawValue == "more" {
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = "More"; item.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "More")
            let menu = NSMenu()
            menu.addItem(NativeMenuAction.item("New App Folder…") { [weak self] in self?.itemDialogs.createFolder() })
            menu.addItem(NativeMenuAction.item("Duplicate Dock") { [weak self] in self?.duplicateDock() })
            menu.addItem(NativeMenuAction.item("Delete Dock…") { [weak self] in self?.deleteDock() })
            menu.addItem(.separator())
            menu.addItem(NativeMenuAction.item("Add File or Folder…") { [weak self] in self?.itemDialogs.pickFiles() })
            menu.addItem(NativeMenuAction.item("Add Link…") { [weak self] in self?.itemDialogs.addLink() })
            menu.addItem(NativeMenuAction.item("Add Spacer") { [weak self] in self?.add(DockItem(kind: .spacer, title: "Spacer", symbol: "line.3.vertical")) })
            menu.addItem(.separator())
            menu.addItem(NativeMenuAction.item("Import Backup…") { [weak self] in self?.importBackup() })
            menu.addItem(NativeMenuAction.item("Export Backup…") { [weak self] in self?.exportBackup() })
            item.menu = menu
            return item
        }
        let item = NSToolbarItem(itemIdentifier: identifier)
        let configuration: (String, String, Selector)
        switch identifier.rawValue {
        case "widgets": configuration = ("Widget Library", "square.grid.2x2", #selector(showWidgetLibrary))
        case "group": configuration = ("Group Applications", "folder.badge.plus", #selector(groupSelectedApplications))
        case "new": configuration = ("New Dock", "plus", #selector(newDock))
        case "add": configuration = ("Add Applications", "app.badge", #selector(addApplications))
        case "remove": configuration = ("Remove Item", "minus", #selector(removeSelected))
        default: return nil
        }
        item.label = configuration.0; item.toolTip = configuration.0
        item.image = NSImage(systemSymbolName: configuration.1, accessibilityDescription: configuration.0)
        item.target = self; item.action = configuration.2
        return item
    }

    @objc private func showWidgetLibrary() {
        let profileID = store.active.id
        widgetLibrary = NativeWidgetLibrary(profileName: store.active.name) { [weak self] kind in
            guard let self else { return }
            let item = DockItem.widget(kind)
            do {
                try store.add(item, to: profileID)
                if [.webValue, .custom, .note, .worldClock, .countdown].contains(kind) {
                    application?.openItem(item, in: profileID)
                }
            } catch { application?.report(error.localizedDescription) }
        }
        widgetLibrary?.showWindow(nil); widgetLibrary?.window?.makeKeyAndOrderFront(nil)
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        if item.itemIdentifier.rawValue == "remove" { return items.selectedRow >= 0 }
        if item.itemIdentifier.rawValue == "group" {
            return items.selectedRowIndexes.count >= 2 && items.selectedRowIndexes.allSatisfy {
                store.active.items.indices.contains($0) && store.active.items[$0].kind == .application
            }
        }
        return true
    }

    @objc private func groupSelectedApplications() {
        let ids = Set(items.selectedRowIndexes.compactMap { store.active.items.indices.contains($0) ? store.active.items[$0].id : nil })
        guard ids.count >= 2 else { return }
        let alert = NSAlert(); alert.messageText = "Group Applications"
        let name = NSTextField(string: ""); name.placeholderString = "Folder name"
        name.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = name; alert.addButton(withTitle: "Create Folder"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = name
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.groupApplications(ids, in: store.active.id, name: name.stringValue.isEmpty ? "Folder" : name.stringValue)
            if let index = store.active.items.firstIndex(where: { $0.kind == .folder && Set(($0.children ?? []).map(\.id)) == ids }) {
                items.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                items.scrollRowToVisible(index)
            }
        }
        catch { application?.report(error.localizedDescription) }
    }

    private func add(_ item: DockItem) { do { try store.add(item) } catch { application?.report(error.localizedDescription) } }
    private var itemDialogs: NativeItemDialogs {
        NativeItemDialogs(profileID: store.active.id, store: store, application: application)
    }
    @objc private func newDock() { application?.newDock() }
    @objc private func addApplications() { itemDialogs.pickApplications() }
    @objc private func removeSelected() {
        guard store.active.items.indices.contains(items.selectedRow) else { return }
        var profile = store.active
        let ids = Set(items.selectedRowIndexes.compactMap { store.active.items.indices.contains($0) ? store.active.items[$0].id : nil })
        profile.items.removeAll { ids.contains($0.id) }
        save(profile)
    }
    @objc private func editSelected() {
        guard store.active.items.indices.contains(items.selectedRow) else { return }
        let item = store.active.items[items.selectedRow]
        if item.kind == .folder { application?.openItem(item, in: store.active.id) }
        if item.kind == .widget {
            application?.openItem(item, in: store.active.id)
        }
    }
    private func duplicateDock() {
        do { try store.create(name: store.active.name + " copy", duplicate: true) } catch { application?.report(error.localizedDescription) }
    }
    private func deleteDock() {
        let alert = NSAlert(); alert.messageText = "Delete \(store.active.name)?"
        alert.informativeText = "The dock and its widget data will be removed. Applications and files are not deleted."
        alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            do { try store.deleteActive() } catch { application?.report(error.localizedDescription) }
        }
    }
    private func exportBackup() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "OpenDoc-backup.json"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do { try store.exportData().write(to: url, options: .atomic) } catch { application?.report(error.localizedDescription) }
        }
    }
    private func importBackup() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do { try store.importData(Data(contentsOf: url)) } catch { application?.report(error.localizedDescription) }
        }
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard tableView === items else { return nil }
        return store.active.items[row].id.uuidString as NSString
    }
    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard tableView === items, info.draggingSource as? NSTableView === items else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard tableView === items, let string = info.draggingPasteboard.string(forType: .string), let id = UUID(uuidString: string),
              let index = store.active.items.firstIndex(where: { $0.id == id }) else { return false }
        var profile = store.active
        let item = profile.items.remove(at: index)
        profile.items.insert(item, at: min(profile.items.count, max(0, row > index ? row - 1 : row)))
        save(profile)
        return true
    }
}

/// Round colour swatches for the glass tint, one per supported colour.
final class NativeTintPicker: NSStackView {
    /// Called with whether the selection changed.
    var onChange: ((Bool) -> Void)?
    var selected = "Graphite" {
        didSet {
            swatches.forEach { $0.needsDisplay = true }
            guard selected != oldValue else { return }
            for swatch in swatches where swatch.name == selected || swatch.name == oldValue {
                NSAccessibility.post(element: swatch, notification: .valueChanged)
            }
        }
    }
    private var swatches: [Swatch] = []

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 8
        swatches = DockAppearance.tintColors.map { name in
            let swatch = Swatch(name: name, picker: self)
            addArrangedSubview(swatch)
            return swatch
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel("Tint colour")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    fileprivate func choose(_ name: String) {
        let changed = name != selected
        selected = name
        onChange?(changed)
    }

    fileprivate final class Swatch: NSButton {
        let name: String
        weak var picker: NativeTintPicker?
        init(name: String, picker: NativeTintPicker) {
            self.name = name; self.picker = picker
            super.init(frame: .zero)
            isBordered = false
            title = ""
            toolTip = name == "Accent" ? "System accent colour" : name
            setAccessibilityRole(.radioButton)
            setAccessibilityLabel(toolTip)
            target = self; action = #selector(pick)
            focusRingType = .exterior
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override var intrinsicContentSize: NSSize { NSSize(width: 20, height: 20) }
        @objc private func pick() { picker?.choose(name) }
        override func accessibilityValue() -> Any? { picker?.selected == name ? 1 : 0 }
        override var focusRingMaskBounds: NSRect { bounds }
        override func drawFocusRingMask() { NSBezierPath(ovalIn: bounds).fill() }
        override func draw(_ dirtyRect: NSRect) {
            let isSelected = picker?.selected == name
            let circle = bounds.insetBy(dx: 3, dy: 3)
            if name == "Accent" {
                // A wheel of colours, like the accent choice in System Settings.
                let colors: [NSColor] = [.systemBlue, .systemPurple, .systemPink, .systemRed, .systemOrange, .systemYellow, .systemGreen]
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(ovalIn: circle).addClip()
                for (index, color) in colors.enumerated() {
                    let path = NSBezierPath()
                    let center = NSPoint(x: circle.midX, y: circle.midY)
                    path.move(to: center)
                    path.appendArc(withCenter: center, radius: circle.width, startAngle: CGFloat(index) * 360 / 7, endAngle: CGFloat(index + 1) * 360 / 7)
                    path.close()
                    color.setFill(); path.fill()
                }
                NSGraphicsContext.restoreGraphicsState()
            } else {
                NativeDockStyle.swatch(named: name).setFill()
                NSBezierPath(ovalIn: circle).fill()
            }
            NSColor.black.withAlphaComponent(0.12).setStroke()
            let rim = NSBezierPath(ovalIn: circle.insetBy(dx: 0.25, dy: 0.25)); rim.lineWidth = 0.5; rim.stroke()
            if isSelected {
                NSColor.labelColor.withAlphaComponent(0.6).setStroke()
                let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.75, dy: 0.75)); ring.lineWidth = 1.5; ring.stroke()
            }
        }
    }
}
#endif
