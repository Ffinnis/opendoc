#if os(macOS)
import AppKit

final class NativeWidgetLibrary: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private let search = NSSearchField()
    private let category = NSPopUpButton()
    private let table = NSTableView()
    private let preview = NSStackView()
    private let addButton = NSButton(title: "Add Widget", target: nil, action: nil)
    private var results = WidgetKind.allCases
    private var refreshTimer: Timer?
    private let onAdd: (WidgetKind) -> Void

    init(profileName: String, onAdd: @escaping (WidgetKind) -> Void) {
        self.onAdd = onAdd
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 470), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Widget Library · " + profileName
        panel.isReleasedWhenClosed = false
        panel.center()
        super.init(window: panel)
        panel.delegate = self
        let root = FlippedNativeView(frame: NSRect(x: 0, y: 0, width: 680, height: 470))
        panel.contentView = root
        search.frame = NSRect(x: 20, y: 18, width: 440, height: 28)
        search.placeholderString = "Search widgets"; search.delegate = self
        search.setAccessibilityLabel("Search widgets")
        root.addSubview(search)
        category.addItems(withTitles: ["All Widgets", "Productivity", "Time", "System", "Everyday", "Custom data"])
        category.target = self; category.action = #selector(filter)
        category.frame = NSRect(x: 474, y: 18, width: 186, height: 28)
        root.addSubview(category)
        let scroll = NSScrollView(frame: NSRect(x: 14, y: 60, width: 285, height: 390))
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        table.addTableColumn(NSTableColumn(identifier: .init("widget")))
        table.headerView = nil; table.style = .inset; table.rowHeight = 52
        table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(addSelected)
        table.setAccessibilityIdentifier("widget-library-list")
        scroll.documentView = table; root.addSubview(scroll)
        preview.orientation = .vertical; preview.alignment = .leading; preview.spacing = 18
        preview.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(preview)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 324),
            preview.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            preview.topAnchor.constraint(equalTo: root.topAnchor, constant: 80)
        ])
        addButton.bezelStyle = .rounded; addButton.keyEquivalent = "\r"
        addButton.target = self; addButton.action = #selector(addSelected)
        addButton.frame = NSRect(x: 532, y: 416, width: 128, height: 32)
        root.addSubview(addButton)
        table.reloadData(); table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        panel.initialFirstResponder = search
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.preview.arrangedSubviews.compactMap { $0 as? NativeDockItemView }.forEach { $0.refreshIfNeeded(at: Date()) }
            }
        }
    }
    deinit { refreshTimer?.invalidate() }
    override func close() { refreshTimer?.invalidate(); super.close() }
    func windowWillClose(_ notification: Notification) { refreshTimer?.invalidate() }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let kind = results[row]
        let cell = NSTableCellView()
        let icon = NSImageView(image: NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        icon.frame = NSRect(x: 8, y: 14, width: 24, height: 24)
        let title = NSTextField(labelWithString: kind.title); title.font = .systemFont(ofSize: 13, weight: .medium)
        title.frame = NSRect(x: 44, y: 26, width: 210, height: 18)
        let subtitle = NSTextField(labelWithString: kind.category); subtitle.font = .systemFont(ofSize: 11); subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 44, y: 8, width: 210, height: 15)
        cell.addSubview(icon); cell.addSubview(title); cell.addSubview(subtitle)
        cell.textField = title; cell.imageView = icon
        return cell
    }
    func controlTextDidChange(_ obj: Notification) { filter() }
    @objc private func filter() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        results = WidgetKind.allCases.filter {
            (category.indexOfSelectedItem == 0 || $0.category == category.titleOfSelectedItem)
                && (query.isEmpty || ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(query))
        }
        table.reloadData()
        if !results.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        updatePreview()
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updatePreview() }
    private func updatePreview() {
        preview.arrangedSubviews.forEach { preview.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard results.indices.contains(table.selectedRow) else {
            preview.addArrangedSubview(NSTextField(labelWithString: "No matching widgets"))
            addButton.isEnabled = false
            return
        }
        addButton.isEnabled = true
        let kind = results[table.selectedRow]
        let title = NSTextField(labelWithString: kind.title); title.font = .systemFont(ofSize: 22, weight: .semibold)
        preview.addArrangedSubview(title)
        let tile = NativeDockItemView(item: .widget(kind), iconSize: 44, vertical: false)
        tile.setAccessibilityRole(.image)
        tile.setAccessibilityHelp("Widget preview")
        tile.widthAnchor.constraint(equalToConstant: 190).isActive = true
        tile.heightAnchor.constraint(equalToConstant: 64).isActive = true
        preview.addArrangedSubview(tile)
        let description = NSTextField(wrappingLabelWithString: kind.detail)
        description.textColor = .secondaryLabelColor; description.font = .systemFont(ofSize: 13)
        description.widthAnchor.constraint(equalToConstant: 310).isActive = true
        preview.addArrangedSubview(description)
        let hint = NSTextField(wrappingLabelWithString: kind == .webValue ? "Choose the endpoint and JSON field after adding. Requests refresh every 1–60 minutes." : "Add multiple copies and configure each independently.")
        hint.textColor = .secondaryLabelColor; hint.font = .systemFont(ofSize: 11)
        hint.widthAnchor.constraint(equalToConstant: 310).isActive = true
        preview.addArrangedSubview(hint)
    }
    @objc private func addSelected() {
        guard results.indices.contains(table.selectedRow) else { return }
        let kind = results[table.selectedRow]
        close()
        onAdd(kind)
    }
}
#endif
