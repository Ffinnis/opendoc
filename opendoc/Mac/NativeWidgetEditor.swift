#if os(macOS)
import AppKit

/// A widget's card: its live value in the widget's colour, with the controls
/// for that widget below. Opens from the dock on click, never on hover, so
/// pointing at the dock never activates Open Doc or takes focus.
final class NativeWidgetEditor: NSViewController, NSTextViewDelegate, NSPopoverDelegate {
    let itemID: UUID
    private let store: DockStore
    private weak var dock: NativeDockController?
    private let popover = NSPopover()
    private let content = NSStackView()
    private var header: NativeCardHeader?
    private let value = NativeCard.value()
    private let detail = NSTextField(labelWithString: "")
    private let ring = NativeCardRing()
    private let bar = NativeCardBar()
    private let glasses = NativeCardGlasses()
    private var customView: NativeCustomWidgetView?
    private var timer: Timer?
    private let status = NSTextField(wrappingLabelWithString: "")
    private weak var noteEditor: NSTextView?
    private var noteSaveTimer: Timer?
    private var noteDirty = false
    private var validationMessage: String?
    /// Keeps typing in the new-task field after Return adds a task.
    private var focusNewTask = false
    private var terminationObserver: NSObjectProtocol?
    private var observer: NSObjectProtocol?
    var isShown: Bool { popover.isShown }
    private var item: DockItem? { store.archive.profiles.flatMap(\.items).first { $0.id == itemID } }

    init(itemID: UUID, dock: NativeDockController) {
        self.itemID = itemID; self.store = dock.store; self.dock = dock
        super.init(nibName: nil, bundle: nil)
        popover.behavior = .transient
        popover.delegate = self
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.saveNote() }
        }
        observer = NotificationCenter.default.addObserver(forName: DockStore.changed, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let item = self.item { self.header?.titleField.stringValue = item.title } else { self.close() }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: NativeCard.width, height: 300))
        content.orientation = .vertical; content.alignment = .leading; content.spacing = NativeCard.spacing
        view.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: NativeCard.inset),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: NativeCard.inset),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -NativeCard.inset)
        ])
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        render()
    }
    func show(relativeTo anchor: NSView, rect: NSRect? = nil) {
        dock?.reveal(animated: false)
        popover.contentViewController = self
        _ = view
        popover.contentSize = view.frame.size
        popover.animates = !NativeMotion.reducesMotion
        let edge: NSRectEdge = dock?.profile?.appearance.position == "Left" ? .maxX : dock?.profile?.appearance.position == "Right" ? .minX : .maxY
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: rect ?? anchor.bounds, of: anchor, preferredEdge: edge)
        view.window?.makeKeyAndOrderFront(nil)
        if let noteEditor { view.window?.makeFirstResponder(noteEditor) }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshValue() }
        }
    }
    @discardableResult func close() -> Bool {
        guard saveNote() else { return false }
        popover.performClose(nil)
        return true
    }
    func popoverShouldClose(_ popover: NSPopover) -> Bool { saveNote() }
    func popoverDidClose(_ notification: Notification) {
        timer?.invalidate(); noteSaveTimer?.invalidate()
        customView?.stopRefreshing()
        popover.contentViewController = nil
        dock?.scheduleHide()
    }
    deinit {
        timer?.invalidate(); noteSaveTimer?.invalidate()
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: Layout

    private func add(_ view: NSView, fill: Bool = true) {
        content.addArrangedSubview(view)
        if fill { view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
    }

    /// Centres a view across the card.
    private func centered(_ view: NSView) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.setViews([view], in: .center)
        add(row)
    }

    private func caption(_ text: String) { add(NativeCard.caption(text)) }

    private func hero(detail text: String? = nil) {
        add(value)
        if let text { detail.stringValue = text; add(detail) }
    }

    /// What the card is about, without repeating the widget's name.
    private func subtitle(for kind: WidgetKind, item: DockItem) -> String {
        switch kind {
        case .focus: "\(Int(item.duration / 60))-minute session"
        case .stopwatch: "Keeps counting while this card is closed"
        case .note: "Saved on this Mac"
        case .reminders: item.checklist.isEmpty ? "A local checklist" : "\(item.checklist.filter(\.done).count) of \(item.checklist.count) done"
        case .hydration: "Glasses of water today"
        case .worldClock: NativeWidgetFormat.city(item.timeZone)
        case .countdown: "Counting down"
        case .calendar: "Today"
        case .clock: "Local time"
        case .battery: "This Mac’s battery"
        case .cpu: "Processor usage"
        case .memory: "Memory usage"
        case .webValue: "Value from a JSON endpoint"
        case .custom: "Custom widget"
        }
    }

    private func render() {
        guard let item, let kind = item.widget else { return }
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        let accent = kind.accent
        let header = NativeCardHeader(symbol: kind == .battery ? NativeBattery.symbol(for: NativeBattery.status) : kind.symbol,
                                      color: kind == .battery ? NativeBattery.color(for: NativeBattery.status) : accent,
                                      title: item.title, subtitle: subtitle(for: kind, item: item))
        self.header = header
        add(header)
        value.alignment = .left
        switch kind {
        case .focus:
            ring.color = accent
            centered(ring)
            let running = item.startedAt != nil
            let controls = NativeCard.row([
                NativeCapsuleButton(running ? "Pause" : "Start", style: .primary(accent)) { [weak self] in self?.toggleTimer() },
                NativeCapsuleButton("Reset") { [weak self] in self?.resetTimer() }
            ])
            centered(controls)
            let durations = NSSegmentedControl(labels: ["15 min", "25 min", "50 min"], trackingMode: .selectOne, target: self, action: #selector(changeDuration(_:)))
            durations.selectedSegment = [900.0, 1500, 3000].firstIndex(of: item.duration) ?? -1
            durations.setAccessibilityLabel("Session length")
            centered(durations)
            caption("The timer keeps running when you close this card. No sound or notification is scheduled.")
        case .stopwatch:
            value.alignment = .center
            value.font = NativeDockStyle.valueFont(40)
            add(value)
            centered(NativeCard.row([
                NativeCapsuleButton(item.startedAt != nil ? "Pause" : "Start", style: .primary(accent)) { [weak self] in self?.toggleTimer() },
                NativeCapsuleButton("Reset") { [weak self] in self?.resetTimer() }
            ]))
        case .note:
            let scroll = NSScrollView(); scroll.borderType = .noBorder; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
            let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: NativeCard.width - 64, height: 150))
            editor.delegate = self
            editor.allowsUndo = true
            editor.drawsBackground = false
            noteEditor = editor
            editor.isRichText = false; editor.font = .systemFont(ofSize: 14); editor.string = item.note
            editor.textContainerInset = NSSize(width: 2, height: 4)
            editor.setAccessibilityLabel("Note text")
            editor.autoresizingMask = [.width]
            scroll.documentView = editor
            scroll.heightAnchor.constraint(equalToConstant: 170).isActive = true
            let group = NativeCardGroup([scroll])
            add(group)
            status.stringValue = "Changes save automatically."
            status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
            add(status)
        case .hydration:
            hero(detail: "Resets at midnight.")
            glasses.color = accent
            centered(glasses)
            add(NativeCard.row([
                NativeCapsuleButton("Add a Glass", style: .primary(accent)) { [weak self] in self?.update { $0.count = min(1000, $0.dailyCount + 1); $0.countDay = DockItem.dayKey() } },
                NativeCapsuleButton("Undo") { [weak self] in self?.update { $0.count = max(0, $0.dailyCount - 1); $0.countDay = DockItem.dayKey() } }
            ]), fill: false)
        case .worldClock:
            hero(detail: "")
            let zones = NSPopUpButton()
            zones.addItems(withTitles: TimeZone.knownTimeZoneIdentifiers.sorted())
            zones.setAccessibilityLabel("Time zone")
            zones.selectItem(withTitle: item.timeZone)
            zones.target = self; zones.action = #selector(changeTimeZone(_:))
            add(NativeCardGroup([NativeCard.labeled("Time zone", zones)]))
        case .reminders:
            hero()
            bar.color = accent
            add(bar)
            let list = FlippedNativeView()
            let rows = NSStackView(); rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 6
            rows.translatesAutoresizingMaskIntoConstraints = false
            list.addSubview(rows)
            if item.checklist.isEmpty {
                rows.addArrangedSubview(NativeCard.caption("No tasks yet. Add one below."))
            }
            for task in item.checklist {
                let button = NativeButton(task.text) { [weak self] in
                    self?.update { item in
                        if let index = item.checklist.firstIndex(where: { $0.id == task.id }) { item.checklist[index].done.toggle() }
                    }
                }
                button.setButtonType(.switch); button.state = task.done ? .on : .off
                button.lineBreakMode = .byTruncatingTail
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                rows.addArrangedSubview(button)
                button.widthAnchor.constraint(lessThanOrEqualTo: rows.widthAnchor).isActive = true
            }
            // The list is as tall as its rows and as wide as the visible area,
            // so every task can be scrolled to and titles stay clear of a scroller.
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.borderType = .noBorder
            list.translatesAutoresizingMaskIntoConstraints = false
            scroll.documentView = list
            NSLayoutConstraint.activate([
                rows.topAnchor.constraint(equalTo: list.topAnchor), rows.bottomAnchor.constraint(equalTo: list.bottomAnchor),
                rows.leadingAnchor.constraint(equalTo: list.leadingAnchor), rows.trailingAnchor.constraint(equalTo: list.trailingAnchor),
                list.topAnchor.constraint(equalTo: scroll.contentView.topAnchor), list.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
                list.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
            ])
            scroll.heightAnchor.constraint(equalToConstant: min(132, rows.fittingSize.height)).isActive = true
            let input = NSTextField(string: ""); input.placeholderString = "New task"
            input.setAccessibilityLabel("New task")
            let addTask = NativeCapsuleButton("Add", style: .primary(accent)) { [weak self, weak input] in
                let text = (input?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let self, !text.isEmpty else { return }
                focusNewTask = true
                update { $0.checklist.append(ChecklistItem(text: text)) }
            }
            addTask.keyEquivalent = "\r"
            let entry = NativeCard.row([input, addTask])
            input.setContentHuggingPriority(.defaultLow, for: .horizontal)
            add(NativeCardGroup([scroll, entry]))
            if focusNewTask {
                focusNewTask = false
                DispatchQueue.main.async { [weak input] in input?.window?.makeFirstResponder(input) }
            }
            if item.checklist.contains(where: \.done) {
                add(NativeCapsuleButton("Clear Completed") { [weak self] in self?.update { $0.checklist.removeAll(where: \.done) } }, fill: false)
            }
        case .countdown:
            hero(detail: "")
            let name = NSTextField(string: item.title); name.placeholderString = "Name"
            let date = NSDatePicker(); date.datePickerStyle = .textFieldAndStepper; date.datePickerElements = [.yearMonthDay, .hourMinute]
            date.dateValue = item.deadline ?? Date().addingTimeInterval(86400)
            let save = NativeCapsuleButton("Save", style: .primary(accent)) { [weak self, weak name, weak date] in
                guard let date else { return }
                let title = name?.stringValue ?? "Countdown"
                self?.update { $0.title = title.isEmpty ? "Countdown" : title; $0.deadline = date.dateValue }
            }
            save.keyEquivalent = "\r"
            add(NativeCardGroup([NativeCard.labeled("Name", name), NativeCard.labeled("Ends", date)]))
            add(save, fill: false)
        case .calendar:
            value.font = NativeDockStyle.valueFont(22)
            hero(detail: "Calendar dates. This widget does not access your events.")
            let date = NSDatePicker(); date.datePickerStyle = .clockAndCalendar; date.datePickerElements = .yearMonthDay; date.dateValue = Date()
            date.isBordered = false; date.drawsBackground = false
            centered(date)
        case .clock:
            hero(detail: "")
        case .battery:
            hero(detail: "")
            bar.color = NativeBattery.color(for: NativeBattery.status)
            add(bar)
            caption(NativeBattery.status == nil ? "No battery was reported by this Mac." : "Current charge reported by macOS.")
        case .cpu, .memory:
            hero()
            bar.color = accent
            add(bar)
            status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
            add(status)
            caption(kind == .cpu ? "Usage across all processor cores, sampled once per second." : "Active, wired, and compressed memory. This is a usage estimate, not macOS memory pressure.")
            add(NativeCapsuleButton("Open Activity Monitor") {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
            }, fill: false)
        case .webValue:
            hero()
            buildWebEditor(item)
        case .custom:
            let custom = NativeCustomWidgetView(item: item, store: store)
            customView = custom
            custom.onResize = { [weak self] in self?.resizeToFit() }
            add(custom)
        }
        if kind != .focus && kind != .stopwatch && kind != .calendar { value.font = NativeDockStyle.valueFont(34) }
        refreshValue()
        resizeToFit()
    }

    private func resizeToFit() {
        guard isViewLoaded else { return }
        content.layoutSubtreeIfNeeded()
        let height = max(160, content.fittingSize.height + NativeCard.inset * 2)
        view.setFrameSize(NSSize(width: item?.widget == .custom ? 460 : NativeCard.width, height: height))
        preferredContentSize = view.frame.size
        popover.contentSize = view.frame.size
    }

    // MARK: Notes

    func textDidChange(_ notification: Notification) {
        noteDirty = true
        status.stringValue = "Saving…"
        noteSaveTimer?.invalidate()
        noteSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.saveNote() }
        }
    }
    @discardableResult private func saveNote() -> Bool {
        guard noteDirty, let editor = noteEditor, var item else { return true }
        item.note = editor.string
        do {
            try store.updateItem(item)
            noteDirty = false
            status.stringValue = "Saved"
            return true
        } catch { status.stringValue = error.localizedDescription; status.textColor = .systemOrange; return false }
    }

    // MARK: Web value

    private func buildWebEditor(_ item: DockItem) {
        let configuration = item.web ?? WebWidgetConfiguration()
        status.font = .systemFont(ofSize: 11)
        add(status)
        let name = NSTextField(string: item.title); name.placeholderString = "My metric"
        let endpoint = NSTextField(string: configuration.endpoint); endpoint.placeholderString = "https://example.com/metrics.json"
        let path = NSTextField(string: configuration.keyPath); path.placeholderString = "data.total or results.0.value"
        let suffix = NSTextField(string: configuration.suffix); suffix.placeholderString = "Optional, for example %"
        for (field, label) in [(name, "Name"), (endpoint, "JSON endpoint"), (path, "Field path"), (suffix, "Suffix")] { field.setAccessibilityLabel(label) }
        let interval = NSPopUpButton()
        interval.addItems(withTitles: ["Every minute", "Every 5 minutes", "Every 15 minutes", "Every hour"])
        interval.selectItem(at: [60.0, 300, 900, 3600].firstIndex(of: configuration.refreshInterval) ?? 1)
        interval.setAccessibilityLabel("Refresh interval")
        add(NativeCardGroup([NativeCard.labeled("Name", name), NativeCard.labeled("JSON endpoint", endpoint),
                             NativeCard.labeled("Field path", path), NativeCard.labeled("Suffix", suffix), NativeCard.labeled("Refresh", interval)]))
        let save = NativeCapsuleButton("Save & Refresh", style: .primary(WidgetKind.webValue.accent)) { [weak self, weak name, weak endpoint, weak path, weak suffix, weak interval] in
            guard let self else { return }
            let config = WebWidgetConfiguration(endpoint: endpoint?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                keyPath: path?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", suffix: suffix?.stringValue ?? "",
                refreshInterval: [60.0, 300, 900, 3600][max(0, interval?.indexOfSelectedItem ?? 1)])
            do { try config.validate() } catch {
                validationMessage = "Enter a valid HTTPS endpoint. Field paths use dots, including array indexes."
                status.stringValue = validationMessage ?? ""
                status.textColor = .systemOrange
                return
            }
            validationMessage = nil
            let title = name?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            update { $0.title = title.isEmpty ? "Web value" : title; $0.web = config }
            if let item = self.item { NativeWidgetData.shared.refresh(item) }
        }
        save.keyEquivalent = "\r"
        let refresh = NativeCapsuleButton("Refresh Now") { [weak self] in
            guard let item = self?.item else { return }
            NativeWidgetData.shared.refresh(item)
        }
        refresh.isEnabled = item.web != nil
        add(NativeCard.row([save, refresh]), fill: false)
        caption("Choose a text or number field. Leave the field path empty for a root value. The last value stays visible if an update fails.")
    }

    // MARK: Live values

    private func refreshValue() {
        guard let item else { return }
        let now = Date()
        switch item.widget {
        case .focus:
            let remaining = item.timerValue()
            ring.valueField.stringValue = NativeWidgetFormat.clock(remaining)
            ring.statusField.stringValue = item.startedAt != nil ? (remaining == 0 ? "Complete" : "Focusing") : remaining <= 0 ? "Complete" : remaining < item.duration ? "Paused" : "Ready"
            ring.fraction = item.duration > 0 ? remaining / item.duration : 0
        case .stopwatch: value.stringValue = NativeWidgetFormat.clock(item.timerValue())
        case .clock:
            value.stringValue = now.formatted(date: .omitted, time: .standard)
            detail.stringValue = now.formatted(date: .complete, time: .omitted) + " · " + TimeZone.current.identifier
        case .worldClock:
            value.stringValue = NativeWidgetFormat.time(in: item.timeZone, at: now, seconds: true)
            var style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
            style.timeZone = TimeZone(identifier: item.timeZone) ?? .current
            detail.stringValue = NativeWidgetFormat.city(item.timeZone) + " · " + now.formatted(style)
        case .hydration:
            value.stringValue = item.dailyCount == 1 ? "1 glass" : "\(item.dailyCount) glasses"
            glasses.count = min(8, item.dailyCount)
        case .reminders:
            let open = item.checklist.filter { !$0.done }.count
            value.stringValue = NativeWidgetFormat.tasks(open: open, total: item.checklist.count)
            bar.fraction = item.checklist.isEmpty ? 0 : Double(item.checklist.count - open) / Double(item.checklist.count)
        case .countdown:
            let deadline = item.deadline ?? now
            value.stringValue = NativeWidgetFormat.countdown(deadline.timeIntervalSince(now))
            detail.stringValue = deadline <= now ? "Finished" : "Until " + deadline.formatted(date: .complete, time: .shortened)
        case .calendar:
            value.stringValue = now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .cpu, .memory, .webValue:
            let reading = NativeWidgetData.shared.reading(for: item)
            value.stringValue = reading.value
            status.stringValue = validationMessage ?? reading.detail
            status.textColor = (reading.isError || validationMessage != nil) ? .systemOrange : .secondaryLabelColor
            bar.fraction = NativeWidgetFormat.fraction(from: reading.value) ?? 0
        case .battery:
            let battery = NativeBattery.status
            value.stringValue = battery.map { "\($0.percentage)%" } ?? "—"
            detail.stringValue = battery.map { $0.charging ? "Charging" : "On battery or charged" } ?? ""
            bar.fraction = battery.map { Double($0.percentage) / 100 } ?? 0
        default: value.stringValue = item.title
        }
    }

    // MARK: Actions

    private func toggleTimer() {
        update {
            if $0.startedAt != nil { $0.remaining = $0.timerValue(); $0.startedAt = nil }
            else {
                if $0.widget == .focus && $0.remaining <= 0 { $0.remaining = $0.duration }
                $0.startedAt = Date()
            }
        }
    }
    private func resetTimer() { update { $0.startedAt = nil; $0.remaining = $0.widget == .stopwatch ? 0 : $0.duration } }
    @objc private func changeDuration(_ sender: NSSegmentedControl) {
        // Clicking the selected length sends the action too; it must not reset a session.
        guard (0..<3).contains(sender.selectedSegment), [900.0, 1500, 3000][sender.selectedSegment] != item?.duration else { return }
        update { $0.duration = [900.0, 1500, 3000][sender.selectedSegment]; $0.remaining = $0.duration; $0.startedAt = nil }
    }
    @objc private func changeTimeZone(_ sender: NSPopUpButton) { update { $0.timeZone = sender.titleOfSelectedItem ?? "Europe/London" } }
    private func update(_ change: (inout DockItem) -> Void) {
        guard var item else { return }
        change(&item)
        do { try store.updateItem(item); render() } catch { report(error.localizedDescription) }
    }
    private func report(_ text: String) { let alert = NSAlert(); alert.messageText = text; alert.runModal() }
}

final class NativeButton: NSButton {
    private var handler: () -> Void
    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        if title == "Save" { keyEquivalent = "\r" }
        target = self; action = #selector(invoke)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func invoke() { handler() }
}
#endif
