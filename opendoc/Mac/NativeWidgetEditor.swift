#if os(macOS)
import AppKit

final class NativeWidgetEditor: NSViewController, NSTextViewDelegate, NSPopoverDelegate {
    let itemID: UUID
    private let store: DockStore
    private weak var dock: NativeDockController?
    private let popover = NSPopover()
    private let content = NSStackView()
    private let heading = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")
    private var customView: NativeCustomWidgetView?
    private var timer: Timer?
    private let status = NSTextField(wrappingLabelWithString: "")
    private weak var noteEditor: NSTextView?
    private var noteSaveTimer: Timer?
    private var noteDirty = false
    private var validationMessage: String?
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
                if let item = self.item { self.heading.stringValue = item.title } else { self.close() }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 330))
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 16
        view.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22)
        ])
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

    private func render() {
        guard let item, let kind = item.widget else { return }
        heading.stringValue = item.title
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        content.addArrangedSubview(heading)
        value.font = .monospacedDigitSystemFont(ofSize: 32, weight: .regular)
        content.addArrangedSubview(value)
        refreshValue()
        switch kind {
        case .focus, .stopwatch:
            let controls = NSStackView(views: [NativeButton(item.startedAt == nil ? "Start" : "Pause") { [weak self] in
                self?.update {
                    if $0.startedAt != nil { $0.remaining = $0.timerValue(); $0.startedAt = nil }
                    else {
                        if $0.widget == .focus && $0.remaining <= 0 { $0.remaining = $0.duration }
                        $0.startedAt = Date()
                    }
                }
            }, NativeButton("Reset") { [weak self] in self?.update { $0.startedAt = nil; $0.remaining = $0.widget == .stopwatch ? 0 : $0.duration } }])
            controls.orientation = .horizontal
            content.addArrangedSubview(controls)
            if kind == .focus {
                let durations = NSPopUpButton()
                durations.addItems(withTitles: ["15 minutes", "25 minutes", "50 minutes"])
                durations.selectItem(at: [900.0, 1500, 3000].firstIndex(of: item.duration) ?? 1)
                durations.target = self; durations.action = #selector(changeDuration(_:))
                content.addArrangedSubview(durations)
                caption("The timer keeps running when you close this window. No sound or notification is scheduled.")
            }
        case .note:
            value.isHidden = true
            let scroll = NSScrollView(); scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
            let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 330, height: 150))
            editor.delegate = self
            editor.allowsUndo = true
            noteEditor = editor
            editor.isRichText = false; editor.font = .systemFont(ofSize: 13); editor.string = item.note
            editor.textContainerInset = NSSize(width: 8, height: 8)
            editor.setAccessibilityLabel("Note text")
            scroll.documentView = editor
            content.addArrangedSubview(scroll)
            scroll.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            scroll.heightAnchor.constraint(equalToConstant: 170).isActive = true
            status.stringValue = "Changes save automatically."
            status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
            content.addArrangedSubview(status)
        case .hydration:
            caption("Glasses today. Resets at midnight.")
            content.addArrangedSubview(NativeButton("Add a Glass") { [weak self] in self?.update { $0.count = min(1000, $0.dailyCount + 1); $0.countDay = DockItem.dayKey() } })
            content.addArrangedSubview(NativeButton("Undo") { [weak self] in self?.update { $0.count = max(0, $0.dailyCount - 1); $0.countDay = DockItem.dayKey() } })
        case .worldClock:
            let zones = NSPopUpButton()
            zones.addItems(withTitles: TimeZone.knownTimeZoneIdentifiers.sorted())
            zones.setAccessibilityLabel("Time zone")
            zones.selectItem(withTitle: item.timeZone)
            zones.target = self; zones.action = #selector(changeTimeZone(_:))
            content.addArrangedSubview(zones)
        case .reminders:
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true
            let list = NSStackView(); list.orientation = .vertical; list.alignment = .leading; list.spacing = 8
            for task in item.checklist {
                let button = NativeButton(task.text) { [weak self] in
                    self?.update { item in
                        if let index = item.checklist.firstIndex(where: { $0.id == task.id }) { item.checklist[index].done.toggle() }
                    }
                }
                button.setButtonType(.switch); button.state = task.done ? .on : .off
                list.addArrangedSubview(button)
            }
            list.frame = NSRect(x: 0, y: 0, width: 325, height: CGFloat(max(1, item.checklist.count)) * 26)
            scroll.documentView = list
            content.addArrangedSubview(scroll)
            scroll.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            scroll.heightAnchor.constraint(equalToConstant: 105).isActive = true
            let input = NSTextField(string: ""); input.placeholderString = "New task"
            input.setAccessibilityLabel("New task")
            content.addArrangedSubview(input); input.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            let actions = NSStackView(views: [NativeButton("Add Task") { [weak self, weak input] in
                let text = (input?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { self?.update { $0.checklist.append(ChecklistItem(text: text)) } }
            }, NativeButton("Clear Completed") { [weak self] in self?.update { $0.checklist.removeAll(where: \.done) } }])
            actions.orientation = .horizontal
            content.addArrangedSubview(actions)
        case .countdown:
            let name = NSTextField(string: item.title); name.placeholderString = "Name"
            let date = NSDatePicker(); date.datePickerStyle = .textFieldAndStepper; date.datePickerElements = [.yearMonthDay, .hourMinute]
            date.dateValue = item.deadline ?? Date().addingTimeInterval(86400)
            content.addArrangedSubview(name); content.addArrangedSubview(date)
            content.addArrangedSubview(NativeButton("Save") { [weak self, weak name, weak date] in
                guard let date else { return }
                let title = name?.stringValue ?? "Countdown"
                self?.update { $0.title = title.isEmpty ? "Countdown" : title; $0.deadline = date.dateValue }
            })
        case .calendar:
            value.isHidden = true
            let date = NSDatePicker(); date.datePickerStyle = .clockAndCalendar; date.datePickerElements = .yearMonthDay; date.dateValue = Date()
            content.addArrangedSubview(date)
            caption("Calendar dates. This widget does not access your events.")
        case .clock:
            caption(Date().formatted(date: .complete, time: .omitted))
            caption(TimeZone.current.identifier)
        case .battery:
            caption(NativeBattery.percentage == nil ? "No battery was reported by this Mac." : "Current charge reported by macOS.")
        case .cpu, .memory:
            status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
            content.addArrangedSubview(status)
            status.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            caption(kind == .cpu ? "Usage across all processor cores, sampled once per second." : "Active, wired, and compressed memory. This is a usage estimate, not macOS memory pressure.")
            content.addArrangedSubview(NativeButton("Open Activity Monitor") {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
            })
        case .webValue:
            buildWebEditor(item)
        case .custom:
            value.isHidden = true
            let custom = NativeCustomWidgetView(item: item, store: store)
            customView = custom
            custom.onResize = { [weak self] in self?.resizeToFit() }
            content.addArrangedSubview(custom)
            custom.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        }
        if ![WidgetKind.note, .calendar, .custom].contains(kind) { value.isHidden = false }
        resizeToFit()
    }

    private func resizeToFit() {
        guard isViewLoaded else { return }
        content.layoutSubtreeIfNeeded()
        let height = max(180, content.fittingSize.height + 44)
        view.setFrameSize(NSSize(width: item?.widget == .custom ? 460 : 380, height: height))
        preferredContentSize = view.frame.size
        popover.contentSize = view.frame.size
    }

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

    private func buildWebEditor(_ item: DockItem) {
        let configuration = item.web ?? WebWidgetConfiguration()
        status.font = .systemFont(ofSize: 11)
        content.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        let name = field("Name", value: item.title, placeholder: "My metric")
        let endpoint = field("JSON endpoint", value: configuration.endpoint, placeholder: "https://example.com/metrics.json")
        let path = field("Field path", value: configuration.keyPath, placeholder: "data.total or results.0.value")
        let suffix = field("Suffix", value: configuration.suffix, placeholder: "Optional, for example %")
        let interval = NSPopUpButton()
        interval.addItems(withTitles: ["Every minute", "Every 5 minutes", "Every 15 minutes", "Every hour"])
        interval.selectItem(at: [60.0, 300, 900, 3600].firstIndex(of: configuration.refreshInterval) ?? 1)
        interval.setAccessibilityLabel("Refresh interval")
        content.addArrangedSubview(interval)
        let save = NativeButton("Save & Refresh") { [weak self, weak name, weak endpoint, weak path, weak suffix, weak interval] in
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
        let refresh = NativeButton("Refresh Now") { [weak self] in
            guard let item = self?.item else { return }
            NativeWidgetData.shared.refresh(item)
        }
        refresh.isEnabled = item.web != nil
        let actions = NSStackView(views: [save, refresh]); actions.orientation = .horizontal
        content.addArrangedSubview(actions)
        caption("Choose a text or number field. Leave the field path empty for a root value. The last value stays visible if an update fails.")
    }

    private func field(_ label: String, value: String, placeholder: String) -> NSTextField {
        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 11, weight: .medium); title.textColor = .secondaryLabelColor
        let input = NSTextField(string: value); input.placeholderString = placeholder
        input.setAccessibilityLabel(label)
        let group = NSStackView(views: [title, input]); group.orientation = .vertical; group.alignment = .leading; group.spacing = 5
        content.addArrangedSubview(group)
        group.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        input.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        return input
    }

    private func caption(_ text: String) {
        let field = NSTextField(wrappingLabelWithString: text); field.font = .systemFont(ofSize: 12); field.textColor = .secondaryLabelColor
        content.addArrangedSubview(field)
        field.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }
    private func refreshValue() {
        guard let item else { return }
        switch item.widget {
        case .focus, .stopwatch:
            let time = Int(item.timerValue()); value.stringValue = String(format: "%02d:%02d", time / 60, time % 60)
        case .clock: value.stringValue = Date().formatted(date: .omitted, time: .standard)
        case .worldClock:
            let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: item.timeZone); formatter.dateFormat = "HH:mm:ss"
            value.stringValue = formatter.string(from: Date())
        case .hydration: value.stringValue = "\(item.dailyCount) / 8"
        case .reminders: value.stringValue = "\(item.checklist.filter { !$0.done }.count) tasks"
        case .countdown:
            let seconds = max(0, Int((item.deadline ?? Date()).timeIntervalSinceNow))
            value.stringValue = "\(seconds / 86400)d \((seconds % 86400) / 3600)h \((seconds % 3600) / 60)m"
        case .cpu, .memory, .webValue:
            let reading = NativeWidgetData.shared.reading(for: item)
            value.stringValue = reading.value
            status.stringValue = validationMessage ?? reading.detail
            status.textColor = (reading.isError || validationMessage != nil) ? .systemOrange : .secondaryLabelColor
        case .battery: value.stringValue = NativeBattery.percentage.map { "\($0)%" } ?? "—"
        default: value.stringValue = item.title
        }
    }
    @objc private func changeDuration(_ sender: NSPopUpButton) {
        update { $0.duration = [900.0, 1500, 3000][sender.indexOfSelectedItem]; $0.remaining = $0.duration; $0.startedAt = nil }
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
