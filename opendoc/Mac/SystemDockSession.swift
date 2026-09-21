#if os(macOS)
import AppKit
import Darwin

/// Changes only the system Dock's visibility preferences, never its pinned items.
/// A separate copy of the executable restores the saved preferences after a crash.
enum SystemDockSession {
    struct Snapshot: Codable {
        var ownerPID: Int32
        var autoHide: Bool?
        var delay: Double?
    }

    static let domain = "com.apple.dock" as CFString
    static let managedDelay = 3600.0
    static var snapshotURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenDoc/system-dock-session.json")
    }
    static var isActive: Bool { FileManager.default.fileExists(atPath: snapshotURL.path) }

    static func begin() throws {
        try withSessionLock(at: snapshotURL) { try beginLocked() }
    }

    private static func beginLocked() throws {
        if let data = try? Data(contentsOf: snapshotURL), let old = try? JSONDecoder().decode(Snapshot.self, from: data) {
            if old.ownerPID == getpid() { return }
            if kill(old.ownerPID, 0) == 0 {
                throw NSError(domain: "OpenDoc", code: 1, userInfo: [NSLocalizedDescriptionKey: "Another Open Doc process is already managing the system Dock."])
            }
            try restoreLocked(at: snapshotURL)
        }
        CFPreferencesAppSynchronize(domain)
        let snapshot = Snapshot(ownerPID: getpid(), autoHide: CFPreferencesCopyAppValue("autohide" as CFString, domain) as? Bool,
                                delay: CFPreferencesCopyAppValue("autohide-delay" as CFString, domain) as? Double)
        try FileManager.default.createDirectory(at: snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: snapshotURL, options: .atomic)
        guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        let watcher = Process()
        watcher.executableURL = executable
        watcher.arguments = ["--restore-dock-after-exit", String(getpid()), snapshotURL.path]
        watcher.standardInput = FileHandle.nullDevice
        watcher.standardOutput = FileHandle.nullDevice
        watcher.standardError = FileHandle.nullDevice
        do { try watcher.run() } catch {
            try? FileManager.default.removeItem(at: snapshotURL)
            throw error
        }
        CFPreferencesSetAppValue("autohide" as CFString, kCFBooleanTrue, domain)
        CFPreferencesSetAppValue("autohide-delay" as CFString, managedDelay as CFNumber, domain)
        guard CFPreferencesAppSynchronize(domain) else {
            try? restoreLocked(at: snapshotURL)
            throw CocoaError(.fileWriteUnknown)
        }
        restartDock()
    }

    static func restore(at url: URL = snapshotURL, expectedOwner: Int32) throws {
        try withSessionLock(at: url) { try restoreLocked(at: url, expectedOwner: expectedOwner) }
    }

    private static func restoreLocked(at url: URL, expectedOwner: Int32? = nil) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let saved = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        if let expectedOwner, saved.ownerPID != expectedOwner { return }
        CFPreferencesAppSynchronize(domain)
        // Respect manual changes made while Open Doc was running.
        if CFPreferencesCopyAppValue("autohide-delay" as CFString, domain) as? Double == managedDelay {
            CFPreferencesSetAppValue("autohide-delay" as CFString, saved.delay.map { $0 as CFNumber }, domain)
            if CFPreferencesCopyAppValue("autohide" as CFString, domain) as? Bool == true {
                CFPreferencesSetAppValue("autohide" as CFString, saved.autoHide.map { $0 as CFBoolean }, domain)
            }
            guard CFPreferencesAppSynchronize(domain) else { throw CocoaError(.fileWriteUnknown) }
            restartDock()
        }
        try FileManager.default.removeItem(at: url)
    }

    // Lock a stable sibling, not the snapshot inode replaced by atomic writes.
    // Keep ownership checks, preference writes, and snapshot removal together.
    static func withSessionLock<T>(at url: URL, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno != EINTR { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    static func runRecoveryWatcher(parent: Int32, snapshot: URL) {
        while kill(parent, 0) == 0 {
            if !FileManager.default.fileExists(atPath: snapshot.path) { return }
            Thread.sleep(forTimeInterval: 1)
        }
        try? restore(at: snapshot, expectedOwner: parent)
    }

    private static func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
#endif
