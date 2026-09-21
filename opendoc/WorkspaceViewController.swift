#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers

final class WorkspaceViewController: UIViewController, UIDocumentPickerDelegate {
    let store: DockStore
    private let sidebar = UIStackView()
    private let body = UIStackView()
    private let scroll = UIScrollView()
    private let preview = DockPreviewView()
    private let sidebarContainer = UIView()
    private let contentContainer = UIView()
    private var sidebarWidth: NSLayoutConstraint!
    private var section = "My docks"
    private var libraryFilter = "All widgets"
    private var libraryQuery = ""
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var pickingBackup = false

    init(store: DockStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        UIDevice.current.isBatteryMonitoringEnabled = true
        sidebarContainer.backgroundColor = Palette.sidebar
        sidebar.axis = .vertical
        sidebar.spacing = 7
        let sidebarScroll = UIScrollView()
        sidebarContainer.addSubview(sidebarScroll)
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebarScroll.addSubview(sidebar)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(scroll)
        scroll.pin(to: contentContainer)
        scroll.alwaysBounceVertical = true
        body.axis = .vertical
        body.spacing = 25
        scroll.addSubview(body)
        body.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebarContainer)
        view.addSubview(contentContainer)
        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        sidebarWidth = sidebarContainer.widthAnchor.constraint(equalToConstant: 224)
        NSLayoutConstraint.activate([
            sidebarWidth, sidebarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor), sidebarContainer.topAnchor.constraint(equalTo: view.topAnchor), sidebarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarScroll.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor), sidebarScroll.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor), sidebarScroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), sidebarScroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: sidebarScroll.contentLayoutGuide.leadingAnchor, constant: 16), sidebar.trailingAnchor.constraint(equalTo: sidebarScroll.contentLayoutGuide.trailingAnchor, constant: -16), sidebar.topAnchor.constraint(equalTo: sidebarScroll.contentLayoutGuide.topAnchor, constant: 26), sidebar.bottomAnchor.constraint(equalTo: sidebarScroll.contentLayoutGuide.bottomAnchor, constant: -20), sidebar.widthAnchor.constraint(equalTo: sidebarScroll.frameLayoutGuide.widthAnchor, constant: -32),
            contentContainer.leadingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor), contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor), contentContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 32), body.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -32), body.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 30), body.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -30), body.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -64)
        ])
        preview.onItem = { [weak self] item in self?.openItem(item) }
        observer = NotificationCenter.default.addObserver(forName: DockStore.changed, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
        render()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.preview.refresh(self.store.active)
            }
        }
        if let error = store.loadError {
            DispatchQueue.main.async { [weak self] in self?.showError(error) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        timer?.invalidate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let compact = view.bounds.width < 700
        if sidebarContainer.isHidden != compact {
            sidebarContainer.isHidden = compact
            sidebarWidth.constant = compact ? 0 : 224
            render()
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        var commands = [UIKeyCommand(title: "New dock", action: #selector(newDock), input: "n", modifierFlags: .command)]
        for index in 0..<min(9, store.archive.profiles.count) {
            commands.append(UIKeyCommand(title: store.archive.profiles[index].name, action: #selector(switchDock(_:)), input: "\(index + 1)", modifierFlags: [.command, .alternate]))
        }
        return commands
    }

    @objc private func switchDock(_ command: UIKeyCommand) {
        guard let input = command.input, let index = Int(input), store.archive.profiles.indices.contains(index - 1) else { return }
        perform { try self.store.select(store.archive.profiles[index - 1].id) }
    }

    private func render() {
        guard isViewLoaded else { return }
        sidebar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        body.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buildSidebar()
        if sidebarContainer.isHidden {
            let navigation = button("\(section) · \(store.active.name)", symbol: "sidebar.left") {}
            navigation.menu = UIMenu(children: ["My docks", "Widget library", "Appearance", "Settings"].map { title in
                UIAction(title: title) { [weak self] _ in self?.navigate(title) }
            } + [UIMenu(title: "Switch dock", children: store.archive.profiles.map { profile in
                UIAction(title: profile.name) { [weak self] _ in self?.perform { try self?.store.select(profile.id) } }
            })])
            navigation.showsMenuAsPrimaryAction = true
            body.addArrangedSubview(navigation)
        }
        switch section {
        case "Widget library": buildLibrary()
        case "Appearance": buildAppearance()
        case "Settings": buildSettings()
        default: buildWorkspace()
        }
    }

    private func buildSidebar() {
        let brandIcon = AppIconView(item: DockItem(kind: .link, title: "Open Doc", symbol: "rectangle.bottomthird.inset.filled", color: "green"), size: 34)
        let brand = stack([brandIcon, stack([label("Open Doc", 19, .semibold), label("A space for your everyday", 10, .regular, Palette.secondary)], spacing: 3)], axis: .horizontal, spacing: 11)
        brand.alignment = .center
        sidebar.addArrangedSubview(brand.padded(6))
        sidebar.setCustomSpacing(29, after: sidebar.arrangedSubviews.last!)
        sidebar.addArrangedSubview(label("WORKSPACE", 9, .semibold, Palette.secondary).padded(10))
        for (title, icon) in [("My docks", "rectangle.bottomthird.inset.filled"), ("Widget library", "square.grid.2x2"), ("Appearance", "slider.horizontal.3")] {
            sidebar.addArrangedSubview(navButton(title, icon: icon, selected: section == title) { [weak self] in self?.navigate(title) })
        }
        let savedHeader = stack([label("SAVED DOCKS", 9, .semibold, Palette.secondary), UIView(), button("", symbol: "plus") { [weak self] in self?.newDock() }], axis: .horizontal)
        savedHeader.alignment = .center
        sidebar.addArrangedSubview(savedHeader)
        sidebar.setCustomSpacing(23, after: sidebar.arrangedSubviews[sidebar.arrangedSubviews.count - 2])
        for profile in store.archive.profiles {
            let selected = profile.id == store.archive.activeID
            let item = navButton(profile.name, icon: profile.symbol, selected: selected && section == "My docks", tint: Palette.color(profile.color)) { [weak self] in
                guard let self else { return }
                section = "My docks"
                perform { try self.store.select(profile.id) }
            }
            item.accessibilityIdentifier = "profile-\(profile.name)"
            sidebar.addArrangedSubview(item)
        }
        let spacer = UIView()
        spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        sidebar.addArrangedSubview(spacer)
        sidebar.addArrangedSubview(navButton("Settings", icon: "gearshape", selected: section == "Settings") { [weak self] in self?.navigate("Settings") })
        let footer = stack([stack([symbol("leaf", size: 13), label("Free by nature.", 12, .medium)], axis: .horizontal, spacing: 8), label("Open source. Yours to make your own.", 10, .regular, Palette.secondary)], spacing: 8).padded(12)
        footer.rounded(12, color: UIColor.white.withAlphaComponent(0.45), border: false)
        sidebar.addArrangedSubview(footer)
    }

    private func navButton(_ title: String, icon: String, selected: Bool, tint: UIColor = Palette.accent, action: @escaping () -> Void) -> UIButton {
        let control = button(title, symbol: icon, action: action)
        control.contentHorizontalAlignment = .leading
        control.configuration?.baseForegroundColor = selected ? Palette.accent : Palette.ink
        control.configuration?.background.backgroundColor = selected ? UIColor(hex: 0xDFE7DA) : .clear
        control.configuration?.imageColorTransformer = UIConfigurationColorTransformer { _ in tint }
        control.accessibilityIdentifier = "nav-\(title)"
        if selected { control.accessibilityTraits.insert(.selected) }
        return control
    }

    private func navigate(_ section: String) {
        self.section = section
        render()
        scroll.setContentOffset(.zero, animated: false)
    }

    private func heading(_ title: String, subtitle: String, trailing: UIView? = nil) {
        let copy = stack([label(title, 30, .semibold), label(subtitle, 13, .regular, Palette.secondary)], spacing: 8)
        let row = stack([copy] + (trailing.map { [UIView(), $0] } ?? []), axis: .horizontal, spacing: 14)
        row.alignment = .center
        body.addArrangedSubview(row)
    }

    private func buildWorkspace() {
        let add = button("New dock", symbol: "plus", filled: true) { [weak self] in self?.newDock() }
        add.accessibilityIdentifier = "new-dock"
        heading("Make room for your day.", subtitle: "Your apps, little helpers, and a little less clutter.", trailing: view.bounds.width < 700 ? nil : add)
        if view.bounds.width < 700 { body.addArrangedSubview(add) }
        let profile = store.active
        let status = label("●  Active dock", 11, .medium, Palette.accent)
        let title = stack([symbol(profile.symbol, size: 20), label(profile.name, 20, .semibold), status, UIView()], axis: .horizontal, spacing: 10)
        title.alignment = .center
        let openDock = button("Open dock", symbol: "macwindow.badge.plus") { [weak self] in
            guard let self else { return }
            DockWindows.open(profile.id, from: self)
        }
        openDock.accessibilityIdentifier = "open-dock-window"
        title.addArrangedSubview(openDock)
        let menu = button("", symbol: "ellipsis") {}
        menu.accessibilityLabel = "Dock actions"
        menu.menu = UIMenu(children: [
            UIAction(title: "Rename dock", image: UIImage(systemName: "pencil")) { [weak self] _ in self?.renameDock() },
            UIAction(title: "Duplicate dock", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in self?.duplicateDock() },
            UIAction(title: "Delete dock", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.deleteDock() }
        ])
        menu.showsMenuAsPrimaryAction = true
        title.addArrangedSubview(menu)
        let editor = stack([title, preview], spacing: 17)
        preview.heightAnchor.constraint(equalToConstant: 300).isActive = true
        preview.configure(profile)
        let caption = stack([symbol("cursorarrow.rays", size: 12, color: Palette.secondary), label("Your dock lives inside this workspace", 11, .regular, Palette.secondary), UIView(), button("Customize", symbol: "slider.horizontal.3") { [weak self] in self?.navigate("Appearance") }], axis: .horizontal, spacing: 7)
        caption.alignment = .center
        editor.addArrangedSubview(caption)
        body.addArrangedSubview(editor)

        let addItem = button("Add item", symbol: "plus") {}
        addItem.accessibilityIdentifier = "add-item"
        addItem.menu = UIMenu(children: [
            UIAction(title: "Website or shortcut", image: UIImage(systemName: "link")) { [weak self] _ in self?.addLink() },
            UIAction(title: "File or folder", image: UIImage(systemName: "folder")) { [weak self] _ in self?.pickFile() },
            UIAction(title: "Widget", image: UIImage(systemName: "square.grid.2x2")) { [weak self] _ in self?.navigate("Widget library") },
            UIAction(title: "Spacer", image: UIImage(systemName: "line.3.vertical")) { [weak self] _ in self?.perform { try self?.store.add(DockItem(kind: .spacer, title: "Spacer", symbol: "line.3.vertical")) } }
        ])
        addItem.showsMenuAsPrimaryAction = true
        let row = stack([label("In this dock", 17, .semibold), label("\(profile.items.count) items", 11, .regular, Palette.secondary), UIView(), addItem], axis: .horizontal, spacing: 10)
        row.alignment = .center
        body.addArrangedSubview(row)
        let list = stack(spacing: 0)
        list.rounded(15)
        if profile.items.isEmpty { list.addArrangedSubview(label("An empty dock, a fresh start. Add an item to make it yours.", 13, .regular, Palette.secondary).padded(24)) }
        for (index, item) in profile.items.enumerated() {
            let icon = AppIconView(item: item, size: 30)
            let copy = stack([label(item.title, 13, .medium), label(item.kind == .widget ? item.widget!.category : item.kind.rawValue.capitalized, 10, .regular, Palette.secondary)], spacing: 3)
            let open = button("", symbol: item.kind == .widget ? "arrow.up.right" : "arrow.up.forward.app") { [weak self] in self?.openItem(item) }
            open.accessibilityLabel = "Open \(item.title)"
            open.isHidden = item.kind == .spacer
            let options = button("", symbol: "ellipsis") {}
            options.accessibilityLabel = "Options for \(item.title)"
            var actions: [UIAction] = []
            if item.kind == .link { actions.append(UIAction(title: "Edit shortcut") { [weak self] _ in self?.addLink(editing: item) }) }
            if index > 0 { actions.append(UIAction(title: "Move earlier", image: UIImage(systemName: "arrow.up")) { [weak self] _ in self?.moveItem(item.id, by: -1) }) }
            if index < profile.items.count - 1 { actions.append(UIAction(title: "Move later", image: UIImage(systemName: "arrow.down")) { [weak self] _ in self?.moveItem(item.id, by: 1) }) }
            actions.append(UIAction(title: "Remove from dock", image: UIImage(systemName: "minus.circle"), attributes: .destructive) { [weak self] _ in
                self?.perform {
                    guard let self else { return }
                    var profile = self.store.active
                    profile.items.removeAll { $0.id == item.id }
                    try self.store.update(profile)
                }
            })
            options.menu = UIMenu(children: actions)
            options.showsMenuAsPrimaryAction = true
            let row = stack([icon, copy, UIView(), open, options], axis: .horizontal, spacing: 12)
            row.alignment = .center
            list.addArrangedSubview(row.padded(12))
            if index != profile.items.count - 1 {
                let line = UIView(); line.backgroundColor = Palette.line
                line.heightAnchor.constraint(equalToConstant: 1).isActive = true
                list.addArrangedSubview(line)
            }
        }
        body.addArrangedSubview(list)
        let discover = stack([stack([label("Small widgets. A useful little difference.", 18, .semibold), label("A timer for focus. A note for later. Find what fits your day.", 12, .regular, Palette.secondary)], spacing: 7), UIView(), button("Explore widgets", symbol: "arrow.right") { [weak self] in self?.navigate("Widget library") }], axis: .horizontal, spacing: 12).padded(22)
        discover.rounded(16, color: UIColor(hex: 0xECF0E7), border: false)
        body.addArrangedSubview(discover)
    }

    private func buildLibrary() {
        heading("Little things. Right here.", subtitle: "Useful widgets for your \(store.active.name) dock. No accounts needed.")
        let search = UISearchTextField()
        search.placeholder = "Find a widget"
        search.text = libraryQuery
        search.heightAnchor.constraint(equalToConstant: 40).isActive = true
        search.addAction(UIAction { [weak self, weak search] _ in
            guard let self else { return }
            libraryQuery = search?.text ?? ""
            rebuildLibraryGrid()
        }, for: .editingChanged)
        body.addArrangedSubview(search)
        let filters = UISegmentedControl(items: ["All widgets", "Productivity", "Time", "Everyday"])
        filters.selectedSegmentIndex = ["All widgets", "Productivity", "Time", "Everyday"].firstIndex(of: libraryFilter) ?? 0
        filters.addAction(UIAction { [weak self, weak filters] _ in
            guard let self, let filters else { return }
            libraryFilter = filters.titleForSegment(at: filters.selectedSegmentIndex) ?? "All widgets"
            rebuildLibraryGrid()
        }, for: .valueChanged)
        body.addArrangedSubview(filters)
        let grid = UIStackView(); grid.axis = .vertical; grid.spacing = 16; grid.tag = 900
        body.addArrangedSubview(grid)
        rebuildLibraryGrid()
    }

    private func rebuildLibraryGrid() {
        guard let grid = body.arrangedSubviews.first(where: { $0.tag == 900 }) as? UIStackView else { return }
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let kinds = WidgetKind.allCases.filter { kind in
            (libraryFilter == "All widgets" || kind.category == libraryFilter) && (libraryQuery.isEmpty || kind.title.localizedCaseInsensitiveContains(libraryQuery))
        }
        let columns = view.bounds.width >= 1100 ? 3 : view.bounds.width >= 700 ? 2 : 1
        var row: UIStackView?
        for (index, kind) in kinds.enumerated() {
            if index % columns == 0 {
                row = stack(axis: .horizontal, spacing: 16)
                row?.distribution = .fillEqually
                grid.addArrangedSubview(row!)
            }
            let sample = WidgetTile(item: .widget(kind))
            sample.heightAnchor.constraint(equalToConstant: 104).isActive = true
            sample.isUserInteractionEnabled = false
            sample.isAccessibilityElement = false
            sample.backgroundColor = kind == .note ? UIColor(hex: 0xF1E6A8) : UIColor(hex: 0xF0F3ED)
            let add = button("Add to dock", symbol: "plus") { [weak self] in self?.perform { try self?.store.add(.widget(kind)) } }
            add.accessibilityIdentifier = "add-widget-\(kind.rawValue)"
            add.accessibilityLabel = "Add \(kind.title) to dock"
            let number = store.active.items.filter { $0.widget == kind }.count
            let titleRow = stack([label(kind.title, 15, .semibold), UIView(), label(number > 0 ? "\(number) added" : kind.category, 10, .medium, Palette.secondary)], axis: .horizontal, spacing: 5)
            let description = label(kind.detail, 12, .regular, Palette.secondary)
            description.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
            let content = stack([sample, titleRow, description, add], spacing: 12).padded(16)
            content.rounded(17)
            row?.addArrangedSubview(content)
        }
        if let row {
            while row.arrangedSubviews.count < columns { row.addArrangedSubview(UIView()) }
        }
        if kinds.isEmpty { grid.addArrangedSubview(label("No widgets match your search.", 15, .regular, Palette.secondary).padded(30)) }
    }

    private func buildAppearance() {
        heading("Feels like your space.", subtitle: "Tune the \(store.active.name) dock. Every change saves automatically.")
        preview.configure(store.active)
        preview.heightAnchor.constraint(equalToConstant: 300).isActive = true
        body.addArrangedSubview(preview)
        let form = stack(spacing: 0)
        form.rounded(16)
        form.addArrangedSubview(choiceRow("Position", detail: "Where your dock sits in the workspace", options: ["Left", "Bottom", "Right"], selected: store.active.appearance.position) { $0.position = $1 })
        form.addArrangedSubview(choiceRow("Material", detail: "A softer backdrop for your items", options: ["Glass", "Light", "Dark"], selected: store.active.appearance.material) { $0.material = $1 })
        form.addArrangedSubview(choiceRow("Wallpaper", detail: "Original artwork, drawn on your device", options: ["Meadow", "Dusk", "Ocean"], selected: store.active.appearance.wallpaper) { $0.wallpaper = $1 })
        let slider = UISlider()
        slider.minimumValue = 36; slider.maximumValue = 88; slider.value = Float(store.active.appearance.size)
        slider.accessibilityLabel = "Dock icon size"
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        slider.addAction(UIAction { [weak self, weak slider] _ in
            guard let self, let slider else { return }
            self.changeAppearance { $0.size = Double(slider.value.rounded()) }
        }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
        form.addArrangedSubview(settingRow("Icon size", detail: "\(Int(store.active.appearance.size)) points", control: slider))
        for (title, detail, key) in [("Show labels", "Names beneath your shortcuts", \DockAppearance.showLabels), ("Auto-hide preview", "Reveal with a pointer hover or a tap", \DockAppearance.autoHide)] {
            let toggle = UISwitch(); toggle.isOn = store.active.appearance[keyPath: key]
            toggle.accessibilityLabel = title
            toggle.addAction(UIAction { [weak self, weak toggle] _ in self?.changeAppearance { $0[keyPath: key] = toggle?.isOn ?? false } }, for: .valueChanged)
            form.addArrangedSubview(settingRow(title, detail: detail, control: toggle))
        }
        body.addArrangedSubview(form)
    }

    private func choiceRow(_ title: String, detail: String, options: [String], selected: String, update: @escaping (inout DockAppearance, String) -> Void) -> UIView {
        let segmented = UISegmentedControl(items: options)
        segmented.selectedSegmentIndex = options.firstIndex(of: selected) ?? 0
        segmented.accessibilityLabel = title
        segmented.addAction(UIAction { [weak self, weak segmented] _ in
            guard let segmented else { return }
            self?.changeAppearance { update(&$0, options[segmented.selectedSegmentIndex]) }
        }, for: .valueChanged)
        return settingRow(title, detail: detail, control: segmented)
    }

    private func settingRow(_ title: String, detail: String, control: UIView) -> UIView {
        let row = stack([stack([label(title, 14, .medium), label(detail, 11, .regular, Palette.secondary)], spacing: 5), UIView(), control], axis: view.bounds.width < 700 ? .vertical : .horizontal, spacing: 15)
        row.alignment = view.bounds.width < 700 ? .fill : .center
        return row.padded(20)
    }

    private func changeAppearance(_ change: (inout DockAppearance) -> Void) {
        var profile = self.store.active
        change(&profile.appearance)
        perform { try self.store.update(profile) }
    }

    private func buildSettings() {
        heading("Yours, wherever you go.", subtitle: "Your workspace is saved locally. No account. No tracking.")
        let backup = stack([
            label("Keep a copy", 19, .semibold),
            label("Export all your docks as a readable JSON file. Importing adds copies and keeps your current docks intact.", 13, .regular, Palette.secondary),
            stack([button("Export docks", symbol: "square.and.arrow.up", filled: true) { [weak self] in self?.exportDocks() }, button("Import docks", symbol: "square.and.arrow.down") { [weak self] in self?.importDocks() }, UIView()], axis: .horizontal)
        ], spacing: 16).padded(24)
        backup.rounded(16)
        body.addArrangedSubview(backup)
        let keyboard = stack([label("A shortcut to your next setup", 19, .semibold), label("⌘ N creates a dock. ⌘ ⌥ 1–9 switches your saved docks while Open Doc is active.", 13, .regular, Palette.secondary)], spacing: 12)
        for (index, profile) in store.archive.profiles.prefix(9).enumerated() {
            let row = stack([symbol(profile.symbol), label(profile.name, 13), UIView(), label("⌘ ⌥ \(index + 1)", 13, .medium, Palette.secondary)], axis: .horizontal)
            row.alignment = .center
            keyboard.addArrangedSubview(row)
        }
        let keyboardCard = keyboard.padded(24); keyboardCard.rounded(16); body.addArrangedSubview(keyboardCard)
        let about = stack([label("Made to be open.", 19, .semibold), label("Open Doc 1.0 · MIT license", 12, .medium, Palette.accent), label("An independent UIKit project inspired by dock-and-widget workspaces. All profiles and widget data stay on this device. Website shortcuts open in your default browser.", 13, .regular, Palette.secondary), label("This UIKit edition runs in an app window. It doesn't replace Apple's Dock, float over other apps, or follow system Focus modes. Widgets use local data; no paid-service integrations are connected.", 12, .regular, Palette.secondary)], spacing: 13).padded(24)
        about.rounded(16); body.addArrangedSubview(about)
    }

    func perform(_ work: () throws -> Void) { do { try work() } catch { showError(error.localizedDescription) } }
    func showError(_ message: String) {
        let alert = UIAlertController(title: "Couldn't complete that", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        (presentedViewController ?? self).present(alert, animated: true)
    }

    @objc private func newDock() {
        prompt(title: "New dock", value: "", placeholder: "A name for this part of your day") { [weak self] name in
            self?.section = "My docks"
            self?.perform { try self?.store.create(name: name) }
        }
    }
    private func renameDock() {
        prompt(title: "Rename dock", value: store.active.name, placeholder: "Dock name") { [weak self] name in
            guard let self else { return }
            var profile = self.store.active; profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            perform { try self.store.update(profile) }
        }
    }
    private func duplicateDock() { perform { try self.store.create(name: store.active.name + " copy", duplicate: true) } }
    private func deleteDock() {
        let alert = UIAlertController(title: "Delete \(store.active.name)?", message: "This removes the saved dock and its widget data. Your apps and files won't be deleted.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete dock", style: .destructive) { [weak self] _ in self?.perform { try self?.store.deleteActive() } })
        present(alert, animated: true)
    }
    private func prompt(title: String, value: String, placeholder: String, action: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = value; $0.placeholder = placeholder }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak alert] _ in action(alert?.textFields?.first?.text ?? "") })
        present(alert, animated: true)
    }

    private func moveItem(_ id: UUID, by offset: Int) {
        var profile = self.store.active
        guard let index = profile.items.firstIndex(where: { $0.id == id }), profile.items.indices.contains(index + offset) else { return }
        profile.items.swapAt(index, index + offset)
        perform { try self.store.update(profile) }
    }

    private func addLink(editing: DockItem? = nil) {
        let alert = UIAlertController(title: editing == nil ? "Add a shortcut" : "Edit shortcut", message: "Use a website address, mailto: link, or shortcuts://run-shortcut?name=YourShortcut", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Name"; $0.text = editing?.title }
        alert.addTextField { $0.placeholder = "https://example.com"; $0.text = editing?.url; $0.keyboardType = .URL; $0.autocapitalizationType = .none }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self, let fields = alert?.textFields else { return }
            let name = (fields[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var address = (fields[1].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !address.contains(":") { address = "https://" + address }
            guard !name.isEmpty, DockArchive.allowedURL(address) != nil else { showError("Enter a name and a valid website or supported shortcut URL."); return }
            var item = editing ?? DockItem(kind: .link, title: name, symbol: "globe", color: "blue")
            item.title = name; item.url = address
            perform { if editing == nil { try self.store.add(item) } else { try self.store.updateItem(item) } }
        })
        present(alert, animated: true)
    }

    private func openItem(_ original: DockItem) {
        guard let item = store.active.items.first(where: { $0.id == original.id }) else { return }
        switch item.kind {
        case .widget:
            let controller = WidgetDetailViewController(itemID: item.id, store: store)
            let navigation = UINavigationController(rootViewController: controller)
            navigation.modalPresentationStyle = .formSheet
            navigation.preferredContentSize = CGSize(width: 480, height: 560)
            present(navigation, animated: true)
        case .link:
            guard let address = item.url, let url = DockArchive.allowedURL(address) else { return }
            UIApplication.shared.open(url) { [weak self] opened in
                if !opened { self?.showError("No app could open this shortcut. Check its address or install the app it needs.") }
            }
        case .file: openFile(item)
        case .spacer: break
        case .application, .trash, .folder: showError("This item opens on the native Mac version of Open Doc.")
        }
    }

    private func pickFile() {
        pickingBackup = false
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .folder], asCopy: false)
        picker.delegate = self
        present(picker, animated: true)
    }
    private func importDocks() {
        pickingBackup = true
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }
    private func exportDocks() {
        perform {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("OpenDoc-backup.json")
            try self.store.exportData().write(to: url, options: .atomic)
            let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
            present(picker, animated: true)
        }
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        perform {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if pickingBackup {
                try self.store.importData(Data(contentsOf: url))
            } else {
                let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                var item = DockItem(kind: .file, title: url.lastPathComponent, symbol: isDirectory ? "folder.fill" : "doc.fill", color: "blue")
                item.bookmark = bookmark
                try self.store.add(item)
            }
        }
    }
    private func openFile(_ item: DockItem) {
        perform {
            guard let bookmark = item.bookmark else { return }
            let controller = try FilePreviewController(bookmark: bookmark)
            controller.modalPresentationStyle = .formSheet
            present(controller, animated: true)
        }
    }
}

#endif
