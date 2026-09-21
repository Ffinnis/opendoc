#if os(macOS)
import AppKit
import Sparkle

/// Sparkle owns update scheduling, signature checks, installation, and relaunch.
final class NativeUpdates: NSObject, NSMenuItemValidation {
    private let controller = SPUStandardUpdaterController(startingUpdater: false,
                                                         updaterDelegate: nil, userDriverDelegate: nil)
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        controller.startUpdater()
    }

    func addMenuItems(to menu: NSMenu) {
        let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        let automatic = NSMenuItem(title: "Automatically Check for Updates", action: #selector(toggleAutomaticChecks), keyEquivalent: "")
        automatic.target = self
        menu.addItem(automatic)
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        guard started else { return }
        controller.checkForUpdates(sender)
    }

    @objc private func toggleAutomaticChecks() {
        guard started else { return }
        controller.updater.automaticallyChecksForUpdates.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleAutomaticChecks) {
            menuItem.state = controller.updater.automaticallyChecksForUpdates ? .on : .off
            return started
        }
        return started && controller.updater.canCheckForUpdates
    }
}
#endif
