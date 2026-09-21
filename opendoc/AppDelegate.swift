#if canImport(UIKit)
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Open Doc", sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        var store = DockStore.shared
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "--ui-testing"), arguments.indices.contains(flag + 1),
           let id = UUID(uuidString: arguments[flag + 1]) {
            store = DockStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("OpenDocTests-\(id).json"))
        }
        #endif
        let activity = options.userActivities.first ?? session.stateRestorationActivity
        if activity?.activityType == DockWindows.activityType,
           let value = activity?.userInfo?["profileID"] as? String, let id = UUID(uuidString: value),
           store.archive.profiles.contains(where: { $0.id == id }) {
            window.rootViewController = DockWindowViewController(profileID: id, store: store)
            session.stateRestorationActivity = activity
        } else {
            window.rootViewController = WorkspaceViewController(store: store)
        }
        window.tintColor = Palette.accent
        window.overrideUserInterfaceStyle = .light
        self.window = window
        window.makeKeyAndVisible()
    }

    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        scene.session.stateRestorationActivity
    }
}

#endif
