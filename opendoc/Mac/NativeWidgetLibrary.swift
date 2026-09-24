#if os(macOS)
import AppKit

final class NativeWidgetLibrary: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private let search = NSSearchField()
    private let category = NSPopUpButton()
    private let table = NSTableView()
    private let preview = NSStackView()
    private let addButton = NSButton(title: "Add Widget", target: nil, action: nil)
    private var results = WidgetKind.allCases
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let kind = results[row]
        let cell = NSTableCellView()
        let badge = NativeCardBadge()
        badge.symbol = kind.symbol
        badge.color = kind.accent
        badge.frame = NSRect(x: 6, y: 10, width: 32, height: 32)
        let title = NSTextField(labelWithString: kind.title); title.font = .systemFont(ofSize: 13, weight: .medium)
        title.frame = NSRect(x: 48, y: 26, width: 206, height: 18)
        let subtitle = NSTextField(labelWithString: kind.category); subtitle.font = .systemFont(ofSize: 11); subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 48, y: 8, width: 206, height: 15)
        cell.addSubview(badge); cell.addSubview(title); cell.addSubview(subtitle)
        cell.textField = title
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
        // The widget at the size and on the glass it will have in the dock.
        let dock = NativeDockPreview(frame: NSRect(x: 0, y: 0, width: 310, height: 116))
        dock.setAccessibilityLabel("\(kind.title) widget preview")
        dock.widthAnchor.constraint(equalToConstant: 310).isActive = true
        dock.heightAnchor.constraint(equalToConstant: 116).isActive = true
        preview.addArrangedSubview(dock)
        dock.show([.widget(kind)], appearance: DockAppearance(), iconSize: 60)
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
