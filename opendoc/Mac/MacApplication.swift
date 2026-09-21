#if os(macOS)
import AppKit

@main
final class MacApplication: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private(set) var store = DockStore.shared
    private var statusItem: NSStatusItem!
    private var docks: [UUID: NativeDockController] = [:]
    private var preferences: NativePreferencesController?
    private var observer: NSObjectProtocol?
    private var isTesting = false
    private var agentServer: NativeAgentServer?
    private let updates = NativeUpdates()

    static func main() {
        let args = CommandLine.arguments
        if args.count >= 2, args[1] == "--cli" {
            exit(NativeAgentCLI.run(Array(args.dropFirst(2))))
        }
        if args == [args[0], "--install-cli"] {
            do {
                let result = try NativeCLIInstaller.install()
                print("Installed \(result.command.path)")
                if let profile = result.shellProfile { print("PATH configured in \(profile.path). Open a new terminal.") }
            } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
            return
        }
        if args.count == 4, args[1] == "--restore-dock-after-exit", let parent = Int32(args[2]) {
            SystemDockSession.runRecoveryWatcher(parent: parent, snapshot: URL(fileURLWithPath: args[3]))
            return
        }
        if args.count == 2, args[1] == "--custom-widget-script" {
            NativeCustomScript.runWorker()
            return
        }
        let app = NSApplication.shared
        let delegate = MacApplication()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--ui-testing"), args.indices.contains(index + 1), let id = UUID(uuidString: args[index + 1]) {
            store = DockStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("NativeOpenDocTest-\(id).json"))
            isTesting = true
        }
        NSApp.setActivationPolicy(.accessory)
        createMenus()
        observer = NotificationCenter.default.addObserver(forName: DockStore.changed, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncDocks() }
        }
        if isTesting {
            showSettings()
            return
        }
        if NativeCLIInstaller.isInstalledApplication { updates.start() }
        migrateDesktopProfile()
        let saved = UserDefaults.standard.stringArray(forKey: "visibleNativeDocks")?.compactMap(UUID.init(uuidString:)) ?? []
        let valid = saved.filter { id in store.archive.profiles.contains { $0.id == id } }
        for id in valid.isEmpty ? [store.active.id] : valid { showDock(id) }
        if !UserDefaults.standard.bool(forKey: "keepAppleDockVisible") { setReplacement(true) }
        if let error = store.loadError { report(error) }
        let commands = NativeAgentCommands(store: store, visible: { [weak self] in self?.isDockVisible($0) ?? false }, setVisible: { [weak self] id, shown in
            if shown { self?.showDock(id) } else { self?.hideDock(id) }
        })
        do { agentServer = try NativeAgentServer { await commands.handle($0) } }
        catch { NSLog("Open Doc agent service: %@", error.localizedDescription) }
        if NativeCLIInstaller.isInstalledApplication {
            do { _ = try NativeCLIInstaller.install() }
            catch { NSLog("Open Doc CLI installation: %@", error.localizedDescription) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        agentServer?.stop()
        if !isTesting { try? SystemDockSession.restore(expectedOwner: ProcessInfo.processInfo.processIdentifier) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func createMenus() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Open Doc")
        appMenu.addItem(actionItem("New Dock…", action: #selector(newDock), key: "n"))
        appMenu.addItem(actionItem("Settings…", action: #selector(showSettings), key: ","))
        appMenu.addItem(actionItem("Install Command Line Tool…", action: #selector(installCommandLineTool)))
        appMenu.addItem(.separator())
        updates.addMenuItems(to: appMenu)
        appMenu.addItem(.separator())
        appMenu.addItem(actionItem("Quit Open Doc", action: #selector(quit), key: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let file = NSMenu(title: "File")
        file.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = file
        main.addItem(fileItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(actionItem("Undo", action: #selector(undoCurrentEdit), key: "z"))
        for (title, selector, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key))
        }
        let redo = actionItem("Redo", action: #selector(redoCurrentEdit), key: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.insertItem(redo, at: 1)
        edit.addItem(.separator())
        edit.addItem(actionItem("Undo Dock Edit", action: #selector(undoDockEdit), key: ""))
        edit.addItem(actionItem("Redo Dock Edit", action: #selector(redoDockEdit), key: ""))
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.bottomthird.inset.filled", accessibilityDescription: "Open Doc")
        statusItem.button?.toolTip = "Open Doc"
        updateStatusMenu()
    }

    private func actionItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func updateStatusMenu() {
        let menu = NSMenu()
        menu.addItem(actionItem("Settings…", action: #selector(showSettings), key: ","))
        menu.addItem(actionItem("Install Command Line Tool…", action: #selector(installCommandLineTool)))
        menu.addItem(actionItem("New Dock…", action: #selector(newDock)))
        menu.addItem(.separator())
        for profile in store.archive.profiles {
            let item = actionItem(profile.name, action: #selector(toggleDock(_:)))
            item.representedObject = profile.id.uuidString
            item.state = docks[profile.id] == nil ? .off : .on
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let replacement = actionItem("Replace Apple’s Dock", action: #selector(toggleReplacement))
        replacement.state = SystemDockSession.isActive ? .on : .off
        menu.addItem(replacement)
        menu.addItem(actionItem("Restore Apple’s Dock", action: #selector(restoreDock)))
        menu.addItem(.separator())
        updates.addMenuItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit Open Doc", action: #selector(quit), key: "q"))
        statusItem?.menu = menu
    }

    @objc func showSettings() {
        if preferences == nil { preferences = NativePreferencesController(store: store, application: self) }
        preferences?.showWindow(nil)
        preferences?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func installCommandLineTool() {
        do {
            let result = try NativeCLIInstaller.install()
            let alert = NSAlert()
            alert.messageText = "opendoc is installed"
            alert.informativeText = "Run opendoc schema or opendoc state from a terminal or agent.\n\n\(result.command.path)" + (result.shellProfile == nil ? "" : "\n\nOpen a new terminal to load the updated PATH.")
            alert.runModal()
        } catch { report(error.localizedDescription) }
    }

    func openItem(_ item: DockItem, in profileID: UUID) {
        showDock(profileID)
        docks[profileID]?.open(item)
    }
    func previewMagnification(in profileID: UUID) {
        showDock(profileID)
        preferences?.window?.orderOut(nil)
        docks[profileID]?.previewMagnification()
    }

    func editDock(_ id: UUID) {
        do { try store.select(id) } catch { report(error.localizedDescription) }
        showSettings()
    }

    @objc func newDock() {
        let alert = NSAlert()
        alert.messageText = "New Dock"
        alert.informativeText = "Choose a name for the additional dock."
        let field = NSTextField(string: "")
        field.placeholderString = "Dock name"
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                var profile = DockProfile(name: name, symbol: "square.grid.2x2", color: "green", items: [])
                profile.appearance.position = docks.values.contains(where: { $0.profile?.appearance.position == "Right" }) ? "Left" : "Right"
                profile.appearance.size = 48
                profile.appearance.showLabels = false
                profile.items = [.widget(.clock)]
                try store.create(profile)
                showDock(profile.id)
                showSettings()
            } catch { report(error.localizedDescription) }
        }
    }

    func showDock(_ id: UUID) {
        guard store.archive.profiles.contains(where: { $0.id == id }) else { return }
        if let controller = docks[id] { controller.window?.orderFrontRegardless(); return }
        let controller = NativeDockController(profileID: id, store: store, application: self)
        docks[id] = controller
        controller.showWindow(nil)
        controller.window?.orderFrontRegardless()
        docks.values.forEach { $0.positionPanel() }
        saveVisibleDocks()
        if !isTesting && !SystemDockSession.isActive && !UserDefaults.standard.bool(forKey: "keepAppleDockVisible") {
            setReplacement(true)
        }
    }

    func hideDock(_ id: UUID) {
        docks.removeValue(forKey: id)?.close()
        if docks.isEmpty && !isTesting {
            // Temporarily restore the system Dock without changing the replacement preference.
            // Showing a dock again must resume the user's chosen replacement mode.
            do { try SystemDockSession.restore(expectedOwner: ProcessInfo.processInfo.processIdentifier) } catch { report(error.localizedDescription) }
        }
        docks.values.forEach { $0.positionPanel() }
        saveVisibleDocks()
    }

    func isDockVisible(_ id: UUID) -> Bool { docks[id] != nil }

    @objc private func toggleDock(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String, let id = UUID(uuidString: text) else { return }
        if docks[id] == nil { showDock(id) } else { hideDock(id) }
    }

    private func saveVisibleDocks() {
        if !isTesting { UserDefaults.standard.set(docks.keys.map(\.uuidString), forKey: "visibleNativeDocks") }
        updateStatusMenu()
        preferences?.refresh()
    }

    private func syncDocks() {
        for id in Array(docks.keys) {
            if !store.archive.profiles.contains(where: { $0.id == id }) { hideDock(id) }
            else { docks[id]?.reload() }
        }
        preferences?.refresh()
        updateStatusMenu()
    }

    @objc private func toggleReplacement() { setReplacement(!SystemDockSession.isActive) }
    @objc private func restoreDock() { setReplacement(false) }

    func setReplacement(_ enabled: Bool) {
        guard !isTesting else { return }
        do {
            if enabled {
                if docks.isEmpty { showDock(store.active.id) }
                try SystemDockSession.begin()
            } else { try SystemDockSession.restore(expectedOwner: ProcessInfo.processInfo.processIdentifier) }
            UserDefaults.standard.set(!enabled, forKey: "keepAppleDockVisible")
        } catch { report(error.localizedDescription) }
        updateStatusMenu()
        preferences?.refresh()
        docks.values.forEach { $0.positionPanel() }
    }

    @objc private func undoDockEdit() { store.undoManager.undo() }
    @objc private func redoDockEdit() { store.undoManager.redo() }
    private var currentUndoManager: UndoManager? {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView { return editor.undoManager }
        return store.undoManager
    }
    @objc private func undoCurrentEdit() { currentUndoManager?.undo() }
    @objc private func redoCurrentEdit() { currentUndoManager?.redo() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undoCurrentEdit) { return currentUndoManager?.canUndo == true }
        if menuItem.action == #selector(redoCurrentEdit) { return currentUndoManager?.canRedo == true }
        if menuItem.action == #selector(undoDockEdit) { return store.undoManager.canUndo }
        if menuItem.action == #selector(redoDockEdit) { return store.undoManager.canRedo }
        return true
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func report(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Open Doc"
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Import real pinned applications into a new profile; keep prior work intact.
    private func migrateDesktopProfile() {
        guard !UserDefaults.standard.bool(forKey: "nativeDockImported") else { return }
        do {
            var profile = DockProfile(name: "Desktop", symbol: "square.grid.2x2", color: "green", items: [])
            profile.appearance.size = 44
            profile.appearance.showLabels = false
            let apps = NativeApplications.pinnedApplications()
            profile.items = [.widget(.focus)] + apps
            profile.items.insert(.widget(.calendar), at: min(3, profile.items.count))
            profile.items.append(DockItem(kind: .spacer, title: "Spacer", symbol: "line.3.vertical"))
            profile.items.append(.widget(.clock))
            profile.items.append(DockItem(kind: .trash, title: "Trash", symbol: "trash"))
            try store.create(profile)
            UserDefaults.standard.set(true, forKey: "nativeDockImported")
        } catch { report(error.localizedDescription) }
    }
}

enum NativeApplications {
    static func item(for url: URL) -> DockItem {
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return DockItem(kind: .application, title: name, symbol: "app", url: url.absoluteString)
    }

    static func pinnedApplications() -> [DockItem] {
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        let values = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] ?? []
        var urls = [finder]
        for value in values {
            guard let tile = value["tile-data"] as? [String: Any], let file = tile["file-data"] as? [String: Any],
                  let address = file["_CFURLString"] as? String, let url = URL(string: address),
                  url.isFileURL, url.pathExtension == "app", FileManager.default.fileExists(atPath: url.path),
                  !urls.contains(url) else { continue }
            urls.append(url)
        }
        if urls.count == 1 {
            urls += NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleURL)
        }
        return urls.filter { $0 != Bundle.main.bundleURL }.map { item(for: $0) }
    }

    static func icon(for item: DockItem) -> NSImage {
        if item.kind == .application, let address = item.url, let url = URL(string: address) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if item.kind == .folder {
            let children = Array((item.children ?? []).prefix(4))
            let icons = children.map { icon(for: $0) }
            return NSImage(size: NSSize(width: 64, height: 64), flipped: false) { bounds in
                if icons.isEmpty {
                    NSImage(systemSymbolName: "folder", accessibilityDescription: item.title)?.draw(in: bounds.insetBy(dx: 16, dy: 16))
                }
                let side: CGFloat = icons.count > 2 ? 18 : icons.count == 1 ? 28 : 23
                let gap: CGFloat = 3
                for (index, image) in icons.enumerated() {
                    let columns = min(2, icons.count)
                    let width = CGFloat(columns) * side + CGFloat(columns - 1) * gap
                    let x = (bounds.width - width) / 2 + CGFloat(index % 2) * (side + gap)
                    let y: CGFloat = icons.count > 2 ? 34 - CGFloat(index / 2) * (side + gap) : (bounds.height - side) / 2
                    image.draw(in: NSRect(x: x, y: y, width: side, height: side))
                }
                return true
            }
        }

        if item.kind == .trash {
            return NSImage(named: NSImage.trashEmptyName) ?? NSImage(systemSymbolName: "trash", accessibilityDescription: "Trash")!
        }
        if item.kind == .file, let data = item.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        return NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title) ?? NSImage(named: NSImage.applicationIconName)!
    }

    static func unpinnedURLs(_ urls: [URL], in items: [DockItem]) -> [URL] {
        var seen = Set(items.flatMap(\.containedItems).compactMap(\.applicationURL))
        return urls.filter { seen.insert($0.standardizedFileURL.resolvingSymlinksInPath()).inserted }
    }

    static func isRunning(_ item: DockItem) -> Bool {
        let urls = Set(item.containedItems.compactMap(\.applicationURL))
        guard !urls.isEmpty else { return false }
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL.map { urls.contains($0.standardizedFileURL.resolvingSymlinksInPath()) } == true
        }
    }

    static func runningCount(_ item: DockItem) -> Int {
        runningCount(item, runningURLs: NSWorkspace.shared.runningApplications.compactMap(\.bundleURL))
    }

    static func runningCount(_ item: DockItem, runningURLs: [URL]) -> Int {
        let contained = Set(item.containedItems.compactMap(\.applicationURL))
        guard !contained.isEmpty else { return 0 }
        let running = Set(runningURLs.map { $0.standardizedFileURL.resolvingSymlinksInPath() })
        return contained.intersection(running).count
    }
}
#endif
