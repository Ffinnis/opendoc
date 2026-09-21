#if os(macOS)
import AppKit

final class NativeCustomWidgetView: NSView {
    private let store: DockStore
    private let itemID: UUID
    private var item: DockItem? { store.archive.profiles.flatMap(\.items).first { $0.id == itemID } }
    private var draft: CustomWidgetConfiguration
    private var draftName: String
    private var editing: Bool
    private var busy = false
    private var lastError: String?
    private var timer: Timer?
    private var scrollToTop = true
    private var ownHeight: NSLayoutConstraint!
    var onResize: (() -> Void)?
    private let tabs = NSSegmentedControl(labels: ["Widget", "Configure"], trackingMode: .selectOne, target: nil, action: nil)
    private let live = NSStackView()
    private let amount = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private let buttons = NSStackView()
    private let liveStatus = NSTextField(wrappingLabelWithString: "")
    private let scroll = NSScrollView()
    private let form = NSStackView()
    private let footer = NSStackView()
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private var nameField: NSTextField!
    private var sourceField: NSPopUpButton!
    private var endpointField: NSTextField?
    private var selectorField: NSTextField?
    private var attributeField: NSTextField?
    private var intervalField: NSPopUpButton?
    private var stateField: NSTextField!
    private var resetField: NSButton!
    private var renderField: NSTextView!
    private var actionFields: [(UUID, NSTextField, NSTextView)] = []

    init(item: DockItem, store: DockStore) {
        self.store = store; itemID = item.id; draftName = item.title
        draft = item.custom ?? CustomWidgetConfiguration()
        editing = item.custom == nil
        super.init(frame: .zero)
        ownHeight = heightAnchor.constraint(equalToConstant: editing ? 540 : 230); ownHeight.isActive = true
        tabs.target = self; tabs.action = #selector(changeTab)
        tabs.selectedSegment = editing ? 1 : 0
        addSubview(tabs)
        live.orientation = .vertical; live.alignment = .leading; live.spacing = 14
        amount.font = .monospacedDigitSystemFont(ofSize: 34, weight: .medium)
        detail.font = .systemFont(ofSize: 13); detail.textColor = .secondaryLabelColor
        liveStatus.font = .systemFont(ofSize: 11); liveStatus.textColor = .secondaryLabelColor
        progress.isIndeterminate = false; progress.style = .bar; progress.minValue = 0; progress.maxValue = 1
        buttons.orientation = .horizontal; buttons.spacing = 8; buttons.distribution = .fillEqually
        for view in [amount, detail, progress, buttons, liveStatus] { live.addArrangedSubview(view) }
        for view in [detail, progress, buttons, liveStatus] { view.widthAnchor.constraint(equalTo: live.widthAnchor).isActive = true }
        addSubview(live)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        form.orientation = .vertical; form.alignment = .leading; form.spacing = 12
        scroll.documentView = form; addSubview(scroll)
        footer.orientation = .horizontal; footer.spacing = 10
        footer.addArrangedSubview(NativeButton("Preview") { [weak self] in self?.preview() })
        footer.addArrangedSubview(NativeButton("Save Widget") { [weak self] in self?.save() })
        addSubview(footer)
        feedback.font = .systemFont(ofSize: 11); feedback.maximumNumberOfLines = 2
        addSubview(feedback)
        buildForm(); rebuildButtons(); updateMode(); refreshLive()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLive() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { timer?.invalidate() }
    func stopRefreshing() { timer?.invalidate(); timer = nil }

    override func layout() {
        super.layout()
        tabs.frame = NSRect(x: 0, y: bounds.height - 26, width: 205, height: 24)
        let height = live.fittingSize.height
        live.frame = NSRect(x: 0, y: bounds.height - 46 - height, width: bounds.width, height: height)
        scroll.frame = NSRect(x: 0, y: 80, width: bounds.width, height: bounds.height - 120)
        form.setFrameSize(NSSize(width: scroll.contentSize.width - 4, height: form.fittingSize.height))
        if scrollToTop, scroll.contentSize.height > 0 {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, form.frame.height - scroll.contentSize.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
            scrollToTop = false
        }
        footer.frame = NSRect(x: 0, y: 40, width: bounds.width, height: 28)
        feedback.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 32)
    }

    @objc private func changeTab() {
        if tabs.selectedSegment == 1, !editing {
            draft = item?.custom ?? draft
            draftName = item?.title ?? draftName
            buildForm()
        }
        editing = tabs.selectedSegment == 1
        updateMode()
    }
    private func updateMode() {
        live.isHidden = editing; scroll.isHidden = !editing; footer.isHidden = !editing; feedback.isHidden = !editing
        ownHeight.constant = editing ? 540 : 230
        needsLayout = true; onResize?()
    }
    private func rebuildButtons() {
        buttons.arrangedSubviews.forEach { buttons.removeArrangedSubview($0); $0.removeFromSuperview() }
        for action in item?.custom?.actions ?? [] {
            let button = NativeButton(action.title) { [weak self] in self?.perform(action.id) }
            buttons.addArrangedSubview(button)
        }
        if item?.custom?.source == .webpage {
            buttons.addArrangedSubview(NativeButton("Refresh") { [weak self] in
                guard let self, let item else { return }
                lastError = nil; NativeCustomWidgetData.shared.refresh(item); refreshLive()
            })
        }
        if buttons.arrangedSubviews.isEmpty {
            buttons.addArrangedSubview(NativeButton("Configure Widget") { [weak self] in
                self?.tabs.selectedSegment = 1; self?.changeTab()
            })
        }
        for button in buttons.arrangedSubviews.compactMap({ $0 as? NSButton }) {
            button.toolTip = button.title
            button.cell?.lineBreakMode = .byTruncatingTail
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
    }
    private func refreshLive() {
        guard let item else { return }
        let reading = NativeCustomWidgetData.shared.reading(for: item)
        amount.stringValue = reading.output.value
        detail.stringValue = reading.output.detail.isEmpty ? item.title : reading.output.detail
        progress.isHidden = reading.output.progress == nil
        progress.doubleValue = reading.output.progress ?? 0
        liveStatus.stringValue = lastError ?? reading.status
        liveStatus.textColor = lastError != nil || reading.isError ? .systemOrange : .secondaryLabelColor
        buttons.arrangedSubviews.compactMap { $0 as? NSButton }.forEach { $0.isEnabled = !busy }
        needsLayout = true
    }
    private func perform(_ actionID: UUID) {
        guard !busy else { return }
        busy = true; lastError = nil; refreshLive()
        Task { [weak self] in
            guard let self else { return }
            do { try await NativeCustomWidgetData.shared.perform(actionID: actionID, itemID: itemID, store: store) }
            catch { lastError = error.localizedDescription }
            busy = false; refreshLive()
        }
    }

    private func buildForm() {
        scrollToTop = true
        form.arrangedSubviews.forEach { form.removeArrangedSubview($0); $0.removeFromSuperview() }
        actionFields = []; endpointField = nil; selectorField = nil; attributeField = nil; intervalField = nil
        let templates = NSPopUpButton()
        templates.addItems(withTitles: ["Choose a starting point…", "Counter", "Water cups", "Webpage value"])
        templates.target = self; templates.action = #selector(chooseTemplate(_:)); templates.setAccessibilityLabel("Widget template")
        add(templates)
        nameField = field("Name", value: draftName)
        sourceField = NSPopUpButton()
        sourceField.addItems(withTitles: ["Saved state", "Webpage HTML"])
        sourceField.selectItem(at: draft.source == .local ? 0 : 1)
        sourceField.target = self; sourceField.action = #selector(changeSource)
        sourceField.setAccessibilityLabel("Widget source"); labelled("Source", sourceField)
        if draft.source == .webpage {
            endpointField = field("Webpage URL", value: draft.endpoint, placeholder: "https://example.com/product")
            selectorField = field("CSS selector", value: draft.selector, placeholder: ".price, #total, div[data-value]")
            attributeField = field("Attribute", value: draft.attribute, placeholder: "Leave empty for element text")
            let interval = NSPopUpButton(); interval.addItems(withTitles: ["Every minute", "Every 5 minutes", "Every 15 minutes", "Every hour"])
            interval.selectItem(at: [60.0, 300, 900, 3600].firstIndex(of: draft.refreshInterval) ?? 1)
            interval.setAccessibilityLabel("Page refresh interval"); labelled("Refresh", interval); intervalField = interval
            help("Reads returned HTML without page scripts or browser login. For JavaScript-loaded values, use the Web value widget with the site's JSON endpoint.")
        }
        let state = (try? JSONEncoder().encode(draft.initialState)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        stateField = field("Initial state (JSON)", value: state, placeholder: "{\"count\":0,\"goal\":8}")
        stateField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        resetField = NSButton(checkboxWithTitle: "Reset state each day", target: nil, action: nil)
        resetField.state = draft.resetDaily ? .on : .off; add(resetField)
        renderField = code("Display function", value: draft.renderScript, height: 104)
        help("Return { value, detail, progress }. Progress is optional, from 0 to 1. Use state for saved numbers, input.text for the first match, and input.matches for all matches.")
        for (index, action) in draft.actions.enumerated() {
            let title = field("Button \(index + 1)", value: action.title)
            let script = code("Button \(index + 1) action", value: action.script, height: 60)
            actionFields.append((action.id, title, script))
            let remove = NativeButton("Remove Button \(index + 1)") { [weak self] in
                guard let self else { return }
                do { try readDraft(); draft.actions.removeAll { $0.id == action.id }; buildForm() }
                catch { showError(error) }
            }
            add(remove)
        }
        let addButton = NativeButton("Add Button") { [weak self] in
            guard let self else { return }
            do { try readDraft(); draft.actions.append(.init(title: "Action", script: "state.count = (state.count || 0) + 1; return state;")); buildForm() }
            catch { showError(error) }
        }
        addButton.isEnabled = draft.actions.count < 4; add(addButton)
        help("Button actions change state and return it. State is saved on this Mac. Changing initial state resets the current values when saved. Scripts have no file, shell, or network APIs and stop after 2 seconds.")
        form.layoutSubtreeIfNeeded(); needsLayout = true
    }
    @objc private func chooseTemplate(_ sender: NSPopUpButton) {
        switch sender.indexOfSelectedItem {
        case 1: draft = CustomWidgetConfiguration()
        case 2: draft = .water()
        case 3: draft = .webpage()
        default: return
        }
        feedback.stringValue = "Template loaded. Preview it, then save."
        feedback.textColor = .secondaryLabelColor; buildForm()
    }
    @objc private func changeSource() {
        let source: CustomWidgetConfiguration.Source = sourceField.indexOfSelectedItem == 0 ? .local : .webpage
        do { try readDraft(); draft.source = source; buildForm() } catch { showError(error) }
    }
    private func readDraft() throws {
        draftName = nameField.stringValue
        let initial = try JSONDecoder().decode([String: Double].self, from: Data(stateField.stringValue.utf8))
        if initial != draft.initialState { draft.state = initial; draft.stateDay = DockItem.dayKey() }
        draft.initialState = initial; draft.resetDaily = resetField.state == .on
        draft.renderScript = renderField.string
        if let endpointField { draft.endpoint = endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let selectorField { draft.selector = selectorField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let attributeField { draft.attribute = attributeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let intervalField { draft.refreshInterval = [60.0, 300, 900, 3600][max(0, intervalField.indexOfSelectedItem)] }
        draft.actions = actionFields.map { CustomWidgetAction(id: $0.0, title: $0.1.stringValue, script: $0.2.string) }
    }
    private func preview() {
        guard !busy else { return }
        do { try readDraft(); try draft.validate() } catch { showError(error); return }
        busy = true; feedback.stringValue = "Running preview…"; feedback.textColor = .secondaryLabelColor
        footer.arrangedSubviews.compactMap { $0 as? NSButton }.forEach { $0.isEnabled = false }
        let config = draft
        Task { [weak self] in
            guard let self else { return }
            do {
                let output = try await NativeCustomWidgetData.shared.preview(config)
                feedback.stringValue = "\(output.value)\(output.detail.isEmpty ? "" : " · " + output.detail)"
                feedback.textColor = .labelColor
            } catch { showError(error) }
            busy = false; footer.arrangedSubviews.compactMap { $0 as? NSButton }.forEach { $0.isEnabled = true }
        }
    }
    private func save() {
        guard !busy, var item else { return }
        do {
            try readDraft(); try draft.validate()
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            item.title = name.isEmpty ? "Custom widget" : name; item.custom = draft
            try store.updateItem(item)
            lastError = nil; NativeCustomWidgetData.shared.refresh(item)
            rebuildButtons(); tabs.selectedSegment = 0; editing = false; updateMode(); refreshLive()
        } catch { showError(error) }
    }
    private func showError(_ error: Error) { feedback.stringValue = error.localizedDescription; feedback.textColor = .systemOrange }
    private func add(_ view: NSView) {
        form.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true
    }
    private func labelled(_ title: String, _ control: NSView) {
        let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor; add(label); add(control)
    }
    private func field(_ title: String, value: String, placeholder: String = "") -> NSTextField {
        let field = NSTextField(string: value); field.placeholderString = placeholder
        field.setAccessibilityLabel(title); labelled(title, field); return field
    }
    private func code(_ title: String, value: String, height: CGFloat) -> NSTextView {
        let scroll = NSScrollView(); scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 392, height: height))
        editor.isRichText = false; editor.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.allowsUndo = true; editor.string = value; editor.textContainerInset = NSSize(width: 6, height: 6)
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.setAccessibilityLabel(title); scroll.documentView = editor
        labelled(title, scroll); scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        return editor
    }
    private func help(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text); label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor; add(label)
    }
}
#endif
