#if os(macOS)
import Foundation

enum NativeCLIInstaller {
    struct Installation {
        let command: URL
        let shellProfile: URL?
    }
    static let marker = "# Open Doc managed command-line launcher v1"

    static var isInstalledApplication: Bool {
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/")
    }

    static func install(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                        executable: URL? = Bundle.main.executableURL,
                        environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Installation {
        guard let executable else { throw AgentTransport.failure("Open Doc's executable could not be found.") }
        let bin = home.appendingPathComponent(".local/bin", isDirectory: true)
        let command = bin.appendingPathComponent("opendoc")
        let fm = FileManager.default
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        // Never overwrite an unrelated executable, including a dangling symlink.
        if let attributes = try? fm.attributesOfItem(atPath: command.path) {
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let previous = try? String(contentsOf: command, encoding: .utf8), previous.contains(marker) else {
                throw AgentTransport.failure("\(command.path) already exists and is not managed by Open Doc.")
            }
        }
        func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = """
        #!/bin/sh
        \(marker)
        binary=\(quote(executable.path))
        if [ ! -x "$binary" ]; then
            printf '%s\\n' 'Open Doc has moved. Launch the app to repair the opendoc command.' >&2
            exit 1
        fi
        exec "$binary" --cli "$@"

        """
        if (try? String(contentsOf: command, encoding: .utf8)) != script {
            try Data(script.utf8).write(to: command, options: .atomic)
        }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: command.path)
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var profile: URL?
        if !path.contains(bin.path) {
            let shell = URL(fileURLWithPath: environment["SHELL"] ?? "/bin/zsh").lastPathComponent
            guard shell == "zsh" || shell == "bash" else {
                throw AgentTransport.failure("Installed \(command.path). Add \(bin.path) to your \(shell) PATH to use opendoc by name.")
            }
            let target = home.appendingPathComponent(shell == "bash" ? ".bash_profile" : ".zprofile")
            let exists = fm.fileExists(atPath: target.path)
            let previous = exists ? try String(contentsOf: target, encoding: .utf8) : ""
            let pathMarker = "# Open Doc command-line PATH"
            if !previous.contains(pathMarker) {
                let block = """

                \(pathMarker)
                case ":$PATH:" in
                  *":$HOME/.local/bin:"*) ;;
                  *) export PATH="$HOME/.local/bin:$PATH" ;;
                esac

                """
                if exists {
                    let file = try FileHandle(forWritingTo: target)
                    defer { try? file.close() }
                    try file.seekToEnd(); try file.write(contentsOf: Data(block.utf8))
                } else { try Data(block.utf8).write(to: target, options: .atomic) }
            }
            profile = target
        }
        return Installation(command: command, shellProfile: profile)
    }
}
#endif
