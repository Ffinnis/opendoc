#if os(macOS)
import AppKit

enum NativeApplicationWindows {
    static func supportsNewWindow(_ item: DockItem) -> Bool {
        guard item.kind == .application, let url = item.applicationURL,
              let id = Bundle(url: url)?.bundleIdentifier else { return false }
        return command(for: id) != nil
    }

    // Only advertise commands supported by the application's scripting dictionary.
    nonisolated static func command(for bundleID: String) -> String? {
        switch bundleID {
        case "com.apple.finder": return "make new Finder window"
        case "com.apple.Safari": return "make new document"
        case "com.google.Chrome", "org.chromium.Chromium",
             "com.brave.Browser", "com.microsoft.edgemac": return "make new window"
        default: return nil
        }
    }

    static func openNewWindow(_ item: DockItem, completion: @escaping @MainActor (String?) -> Void) {
        guard let url = item.applicationURL, let id = Bundle(url: url)?.bundleIdentifier,
              let command = command(for: id) else { return }
        // Automation consent and an unresponsive target must never block dock animation.
        Task {
            let message = await Task.detached(priority: .userInitiated) { () -> String? in
                let source = "with timeout of 15 seconds\ntell application id \"\(id)\"\n\(command)\nactivate\nend tell\nend timeout"
                guard let script = NSAppleScript(source: source) else { return "Could not prepare the New Window command." }
                var error: NSDictionary?
                script.executeAndReturnError(&error)
                guard let error else { return nil }
                if error[NSAppleScript.errorNumber] as? Int == -1743 {
                    return "Allow Open Doc to control this application in System Settings → Privacy & Security → Automation, then try New Window again."
                }
                return error[NSAppleScript.errorMessage] as? String ?? "The application could not open a new window."
            }.value
            completion(message)
        }
    }
}
#endif
