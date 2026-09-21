#if canImport(UIKit)
import UIKit
import QuickLook

/// Holds the security scope for the lifetime of the presented file browser.
final class FilePreviewController: UINavigationController, QLPreviewControllerDataSource {
    private let rootURL: URL
    private let hasAccess: Bool
    private var selectedURL: URL

    init(bookmark: Data) throws {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
        rootURL = url
        selectedURL = url
        hasAccess = url.startAccessingSecurityScopedResource()
        super.init(nibName: nil, bundle: nil)
        guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let browser = FolderListController(url: url)
            browser.openFile = { [weak self] url in self?.showFile(url) }
            setViewControllers([browser], animated: false)
        } else {
            let preview = QLPreviewController()
            preview.dataSource = self
            setViewControllers([preview], animated: false)
        }
        viewControllers.first?.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if hasAccess { rootURL.stopAccessingSecurityScopedResource() } }

    private func showFile(_ url: URL) {
        selectedURL = url
        let preview = QLPreviewController()
        preview.dataSource = self
        pushViewController(preview, animated: true)
    }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { selectedURL as NSURL }
}

private final class FolderListController: UITableViewController {
    let url: URL
    var openFile: ((URL) -> Void)?
    private var files: [URL] = []
    init(url: URL) { self.url = url; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = url.lastPathComponent
        do {
            files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            if files.isEmpty { tableView.backgroundView = label("This folder is empty.", 14, .regular, Palette.secondary).padded(24) }
        } catch { tableView.backgroundView = label(error.localizedDescription, 14, .regular, Palette.secondary).padded(24) }
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { files.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let file = files[indexPath.row]
        let directory = (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var configuration = cell.defaultContentConfiguration()
        configuration.text = file.lastPathComponent
        configuration.image = UIImage(systemName: directory ? "folder" : "doc")
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let file = files[indexPath.row]
        if (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let controller = FolderListController(url: file)
            controller.openFile = openFile
            navigationController?.pushViewController(controller, animated: true)
        } else { openFile?(file) }
    }
}

#endif
