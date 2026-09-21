#if canImport(UIKit)
import UIKit

enum DockWindows {
    static let activityType = "app.opendoc.dock"

    static func open(_ profileID: UUID, from controller: UIViewController) {
        guard UIApplication.shared.supportsMultipleScenes else {
            let alert = UIAlertController(title: "Multiple windows unavailable", message: "Open dock windows on Mac or an iPad that supports multiple windows.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            controller.present(alert, animated: true)
            return
        }
        let activity = NSUserActivity(activityType: activityType)
        activity.userInfo = ["profileID": profileID.uuidString]
        let existing = UIApplication.shared.openSessions.first {
            $0.stateRestorationActivity?.activityType == activityType && $0.stateRestorationActivity?.userInfo?["profileID"] as? String == profileID.uuidString
        }
        UIApplication.shared.requestSceneSessionActivation(existing, userActivity: activity, options: nil) { error in
            let alert = UIAlertController(title: "Couldn't open dock", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            controller.present(alert, animated: true)
        }
    }
}

final class DockWindowViewController: UIViewController {
    let profileID: UUID
    private let store: DockStore
    private let dock = DockPreviewView()
    private let controls = UIStackView()
    private let content = UIStackView()
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var profile: DockProfile? { store.archive.profiles.first { $0.id == profileID } }

    init(profileID: UUID, store: DockStore) {
        self.profileID = profileID
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        dock.dockOnly = true
        content.axis = .vertical
        content.spacing = 0
        view.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor), content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), content.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controls.axis = .horizontal
        controls.alignment = .center
        content.addArrangedSubview(controls)
        content.addArrangedSubview(dock)
        dock.onItem = { [weak self] item in self?.open(item) }
        observer = NotificationCenter.default.addObserver(forName: DockStore.changed, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if let self, let profile = self.profile { self.dock.refresh(profile) } }
        }
        render()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.window?.windowScene?.title = "\(profile?.name ?? "Dock") · Open Doc"
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        timer?.invalidate()
    }

    private func render() {
        guard let profile else {
            if let session = view.window?.windowScene?.session { UIApplication.shared.requestSceneSessionDestruction(session, options: nil) }
            return
        }
        controls.arrangedSubviews.forEach { $0.removeFromSuperview() }
        controls.addArrangedSubview(label(profile.name, 12, .semibold).padded(10))
        controls.addArrangedSubview(UIView())
        let add = button("", symbol: "plus") {}
        add.accessibilityLabel = "Add widget to \(profile.name)"
        add.menu = UIMenu(title: "Add widget", children: WidgetKind.allCases.map { kind in
            UIAction(title: kind.title, image: UIImage(systemName: kind.symbol)) { [weak self] _ in
                guard let self else { return }
                do { try store.add(.widget(kind), to: profileID) } catch { showError(error) }
            }
        })
        add.showsMenuAsPrimaryAction = true
        controls.addArrangedSubview(add)
        controls.addArrangedSubview(button("", symbol: "slider.horizontal.3") { [weak self] in self?.editDock() })
        dock.configure(profile)
        view.window?.windowScene?.title = "\(profile.name) · Open Doc"
    }

    private func editDock() {
        do { try store.select(profileID) } catch { showError(error); return }
        let workspace = UIApplication.shared.connectedScenes.first {
            ($0.delegate as? SceneDelegate)?.window?.rootViewController is WorkspaceViewController
        }
        UIApplication.shared.requestSceneSessionActivation(workspace?.session, userActivity: nil, options: nil)
    }

    private func open(_ original: DockItem) {
        guard let item = profile?.items.first(where: { $0.id == original.id }) else { return }
        if item.kind == .widget {
            let navigation = UINavigationController(rootViewController: WidgetDetailViewController(itemID: item.id, store: store))
            navigation.modalPresentationStyle = .formSheet
            navigation.preferredContentSize = CGSize(width: 480, height: 560)
            present(navigation, animated: true)
        } else if item.kind == .link, let address = item.url, let url = DockArchive.allowedURL(address) {
            UIApplication.shared.open(url) { [weak self] success in
                if !success { self?.showError(CocoaError(.fileReadUnsupportedScheme)) }
            }
        } else if item.kind == .file {
            guard let bookmark = item.bookmark else { return }
            do {
                let controller = try FilePreviewController(bookmark: bookmark)
                controller.modalPresentationStyle = .formSheet
                present(controller, animated: true)
            } catch { showError(error) }
        }
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "Couldn't complete that", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

#endif
