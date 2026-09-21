#if canImport(UIKit)
import UIKit

final class WidgetDetailViewController: UIViewController {
    private let itemID: UUID
    private let store: DockStore
    private let content = UIStackView()
    private var tile: WidgetTile?
    private var timer: Timer?
    private var item: DockItem? { store.archive.profiles.flatMap(\.items).first { $0.id == itemID } }

    init(itemID: UUID, store: DockStore) {
        self.itemID = itemID
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        let scroll = UIScrollView()
        view.addSubview(scroll)
        scroll.pin(to: view)
        content.axis = .vertical
        content.spacing = 20
        scroll.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 28),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -56)
        ])
        render()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if let self, let item = self.item { self.tile?.refresh(item) } }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        timer?.invalidate()
    }

    private func render() {
        guard let item, let kind = item.widget else { dismiss(animated: true); return }
        title = kind.title
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let tile = WidgetTile(item: item)
        tile.heightAnchor.constraint(equalToConstant: 126).isActive = true
        tile.isUserInteractionEnabled = false
        self.tile = tile
        content.addArrangedSubview(tile)
        switch kind {
        case .focus, .stopwatch: buildTimer(item)
        case .note: buildNote(item)
        case .reminders: buildChecklist(item)
        case .hydration:
            content.addArrangedSubview(label("One glass at a time. Your count starts fresh each day.", 14, .regular, Palette.secondary))
            content.addArrangedSubview(button("Add a glass", symbol: "plus", filled: true) { [weak self] in
                self?.update { $0.count = min(1000, $0.dailyCount + 1); $0.countDay = DockItem.dayKey() }
            })
            content.addArrangedSubview(button("Undo a glass", symbol: "minus") { [weak self] in
                self?.update { $0.count = max(0, $0.dailyCount - 1); $0.countDay = DockItem.dayKey() }
            })
        case .worldClock:
            content.addArrangedSubview(label("Choose a time zone", 16, .semibold))
            for zone in ["Europe/London", "America/New_York", "America/Los_Angeles", "Europe/Paris", "Asia/Tokyo", "Asia/Novosibirsk", "Australia/Sydney"] {
                content.addArrangedSubview(button(zone.replacingOccurrences(of: "_", with: " "), symbol: item.timeZone == zone ? "checkmark.circle.fill" : "globe") { [weak self] in self?.update { $0.timeZone = zone } })
            }
        case .countdown: buildCountdown(item)
        case .custom: buildCustom(item)
        case .cpu, .memory, .webValue:
            content.addArrangedSubview(label("Configure and use this widget in Open Doc for Mac.", 14, .regular, Palette.secondary))
        case .calendar:
            let picker = UICalendarView()
            picker.calendar = Calendar.current
            picker.locale = Locale.current
            picker.fontDesign = .rounded
            picker.setVisibleDateComponents(Calendar.current.dateComponents([.year, .month], from: Date()), animated: false)
            content.addArrangedSubview(picker)
            content.addArrangedSubview(label("A local calendar. This widget doesn't read your events.", 12, .regular, Palette.secondary))
        case .clock:
            content.addArrangedSubview(label(Date().formatted(date: .complete, time: .omitted), 19, .medium))
            content.addArrangedSubview(label("Uses your device's current time zone and clock format.", 13, .regular, Palette.secondary))
        case .battery:
            content.addArrangedSubview(label(UIDevice.current.batteryLevel < 0 ? "This device doesn't report battery information through UIKit. Battery readings work on supported iPhone and iPad devices." : "This reading comes from your device and updates while Open Doc is open.", 14, .regular, Palette.secondary))
        }
    }

    private func buildTimer(_ item: DockItem) {
        let running = item.startedAt != nil
        let isFocus = item.widget == .focus
        content.addArrangedSubview(label(isFocus ? "Give one thing your attention. The timer keeps its place when you switch docks or close the app." : "Time a task. Pause whenever you need to.", 14, .regular, Palette.secondary))
        content.addArrangedSubview(button(running ? "Pause" : "Start", symbol: running ? "pause.fill" : "play.fill", filled: true) { [weak self] in
            self?.update {
                if $0.startedAt != nil { $0.remaining = $0.timerValue(); $0.startedAt = nil }
                else {
                    if $0.widget == .focus && $0.remaining <= 0 { $0.remaining = $0.duration }
                    $0.startedAt = Date()
                }
            }
        })
        content.addArrangedSubview(button("Reset", symbol: "arrow.counterclockwise") { [weak self] in self?.update { $0.startedAt = nil; $0.remaining = $0.widget == .stopwatch ? 0 : $0.duration } })
        if isFocus {
            let durations = UISegmentedControl(items: ["15 min", "25 min", "50 min"])
            durations.selectedSegmentIndex = [900.0, 1500, 3000].firstIndex(of: item.duration) ?? UISegmentedControl.noSegment
            durations.accessibilityLabel = "Focus duration"
            durations.addAction(UIAction { [weak self, weak durations] _ in
                guard let durations else { return }
                self?.update { $0.duration = [900.0, 1500, 3000][durations.selectedSegmentIndex]; $0.remaining = $0.duration; $0.startedAt = nil }
            }, for: .valueChanged)
            content.addArrangedSubview(durations)
            content.addArrangedSubview(label("The timer is silent. No background alerts are scheduled.", 12, .regular, Palette.secondary))
        }
    }

    private func buildNote(_ item: DockItem) {
        let editor = UITextView()
        editor.text = item.note
        editor.font = .preferredFont(forTextStyle: .body)
        editor.textColor = Palette.ink
        editor.rounded(12, color: UIColor(hex: 0xF5EDC4), border: false)
        editor.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        editor.heightAnchor.constraint(equalToConstant: 180).isActive = true
        editor.accessibilityLabel = "Note text"
        content.addArrangedSubview(editor)
        content.addArrangedSubview(button("Save note", symbol: "checkmark", filled: true) { [weak self, weak editor] in
            let text = editor?.text ?? ""
            self?.update { $0.note = text }
        })
    }

    private func buildChecklist(_ item: DockItem) {
        content.addArrangedSubview(label("Your local checklist", 16, .semibold))
        if item.checklist.isEmpty { content.addArrangedSubview(label("Nothing on your list yet. Add a task below.", 13, .regular, Palette.secondary)) }
        for task in item.checklist {
            let row = button(task.text, symbol: task.done ? "checkmark.circle.fill" : "circle") { [weak self] in
                self?.update { item in
                    guard let index = item.checklist.firstIndex(where: { $0.id == task.id }) else { return }
                    item.checklist[index].done.toggle()
                }
            }
            row.contentHorizontalAlignment = .leading
            content.addArrangedSubview(row)
        }
        let field = UITextField()
        field.borderStyle = .roundedRect
        field.placeholder = "Add a task"
        field.accessibilityIdentifier = "checklist-input"
        content.addArrangedSubview(field)
        content.addArrangedSubview(button("Add task", symbol: "plus", filled: true) { [weak self, weak field] in
            let text = (field?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            self?.update { $0.checklist.append(ChecklistItem(text: text)) }
        })
        if item.checklist.contains(where: \.done) {
            content.addArrangedSubview(button("Clear completed") { [weak self] in self?.update { $0.checklist.removeAll(where: \.done) } })
        }
    }

    private func buildCountdown(_ item: DockItem) {
        let name = UITextField()
        name.borderStyle = .roundedRect; name.text = item.title; name.placeholder = "What are you counting down to?"
        name.accessibilityLabel = "Countdown name"
        let date = UIDatePicker()
        date.datePickerMode = .dateAndTime
        date.preferredDatePickerStyle = .compact
        date.date = item.deadline ?? Date().addingTimeInterval(86400)
        date.accessibilityLabel = "Countdown date"
        content.addArrangedSubview(name)
        content.addArrangedSubview(date)
        content.addArrangedSubview(button("Save countdown", symbol: "checkmark", filled: true) { [weak self, weak name, weak date] in
            guard let date else { return }
            let title = (name?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self?.update { $0.title = title.isEmpty ? "Countdown" : title; $0.deadline = date.date }
        })
    }

    private func buildCustom(_ item: DockItem) {
        if item.custom != nil {
            content.addArrangedSubview(label("Configure and run this programmable widget in Open Doc for Mac. Its code and saved state are preserved in this workspace.", 13, .regular, Palette.secondary))
            return
        }
        content.addArrangedSubview(label("Make your own widget with a label, text or value, and an optional link. Values are edited here manually.", 13, .regular, Palette.secondary))
        let title = UITextField(); title.borderStyle = .roundedRect; title.text = item.title; title.placeholder = "Widget name"
        title.accessibilityLabel = "Widget name"
        let value = UITextField(); value.borderStyle = .roundedRect; value.text = item.note; value.placeholder = "Text or value"
        value.accessibilityLabel = "Widget value"
        let link = UITextField(); link.borderStyle = .roundedRect; link.text = item.url; link.placeholder = "Optional https:// link"
        link.keyboardType = .URL; link.autocapitalizationType = .none; link.accessibilityLabel = "Widget link"
        content.addArrangedSubview(title); content.addArrangedSubview(value); content.addArrangedSubview(link)
        content.addArrangedSubview(button("Save widget", symbol: "checkmark", filled: true) { [weak self, weak title, weak value, weak link] in
            let name = (title?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let address = (link?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, address.isEmpty || DockArchive.allowedURL(address) != nil else {
                let alert = UIAlertController(title: "Check the widget", message: "Enter a name and a valid URL, or leave the link empty.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(alert, animated: true)
                return
            }
            let text = value?.text ?? ""
            self?.update { $0.title = name; $0.note = text; $0.url = address.isEmpty ? nil : address }
        })
        if let address = item.url, let url = DockArchive.allowedURL(address) {
            content.addArrangedSubview(button("Open link", symbol: "arrow.up.right") { [weak self] in
                UIApplication.shared.open(url) { opened in
                    guard !opened else { return }
                    let alert = UIAlertController(title: "Couldn't open link", message: "No app could open this URL.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                }
            })
        }
    }

    private func update(_ change: (inout DockItem) -> Void) {
        guard var item else { return }
        change(&item)
        do { try store.updateItem(item); render() }
        catch {
            let alert = UIAlertController(title: "Couldn't save", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}

#endif
