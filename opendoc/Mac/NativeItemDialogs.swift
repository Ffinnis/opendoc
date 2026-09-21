#if os(macOS)
import AppKit
import UniformTypeIdentifiers

/// Shared item dialogs capture their destination without constructing a dock window.
final class NativeItemDialogs {
    private let profileID: UUID
    private let store: DockStore
    private weak var application: MacApplication?

    init(profileID: UUID, store: DockStore, application: MacApplication?) {
        self.profileID = profileID
        self.store = store
        self.application = application
    }

    func createFolder() {
        let alert = NSAlert()
        alert.messageText = "New App Folder"
        let name = NSTextField(string: "")
        name.placeholderString = "Folder name"
        name.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = name
        alert.addButton(withTitle: "Create"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = name
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var folder = DockItem(kind: .folder, title: name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), symbol: "folder.fill")
        if folder.title.isEmpty { folder.title = "Folder" }
        folder.children = []
        do {
            try store.add(folder, to: profileID)
            application?.openItem(folder, in: profileID)
        } catch { application?.report(error.localizedDescription) }
    }

    private func add(_ item: DockItem) {
        do { try store.add(item, to: profileID) }
        catch { application?.report(error.localizedDescription) }
    }

    func pickApplications() {
        let picker = NSOpenPanel()
        picker.title = "Add Applications"
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.allowedContentTypes = [.applicationBundle]
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        picker.begin { [self] response in
            if response == .OK { picker.urls.forEach { self.add(NativeApplications.item(for: $0)) } }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func pickFiles() {
        let picker = NSOpenPanel()
        picker.title = "Add Files or Folders"
        picker.canChooseDirectories = true
        picker.allowsMultipleSelection = true
        picker.begin { [self] response in
            guard response == .OK else { return }
            for url in picker.urls {
                do {
                    var item = DockItem(kind: .file, title: url.lastPathComponent, symbol: "folder")
                    item.bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                    self.add(item)
                } catch { self.application?.report(error.localizedDescription) }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func addLink() {
        let alert = NSAlert()
        alert.messageText = "Add Link"
        let fields = NSStackView()
        fields.orientation = .vertical; fields.spacing = 8
        let title = NSTextField(string: ""); title.placeholderString = "Name"
        let url = NSTextField(string: ""); url.placeholderString = "https://example.com"
        fields.addArrangedSubview(title); fields.addArrangedSubview(url)
        fields.frame = NSRect(x: 0, y: 0, width: 300, height: 58)
        title.widthAnchor.constraint(equalToConstant: 300).isActive = true
        url.widthAnchor.constraint(equalToConstant: 300).isActive = true
        alert.accessoryView = fields
        alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let address = url.stringValue.contains(":") ? url.stringValue : "https://\(url.stringValue)"
            guard !title.stringValue.isEmpty, DockArchive.allowedURL(address) != nil else { application?.report("Enter a name and a valid URL."); return }
            add(DockItem(kind: .link, title: title.stringValue, symbol: "globe", url: address))
        }
    }
}
#endif
