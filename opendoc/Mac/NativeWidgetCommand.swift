#if os(macOS)
import Foundation
import Darwin

/// Trusted local programs are separate from the JavaScript formatter and its native-free worker.
@MainActor
enum NativeWidgetCommand {
    private static var running = 0
    nonisolated static let outputLimit = 65_536

    static func run(_ configuration: WidgetCommandConfiguration) async throws -> CustomWidgetInput {
        try configuration.validate()
        guard configuration.enabled else { throw CustomWidgetError.message("Enable local command execution in Configure before previewing or refreshing this widget.") }
        guard running < 2 else { throw CustomWidgetError.message("Two widget commands are already running. Try refreshing again shortly.") }
        running += 1
        defer { running -= 1 }
        return try await Task.detached(priority: .utility) { try execute(configuration) }.value
    }

    nonisolated private static func execute(_ configuration: WidgetCommandConfiguration) throws -> CustomWidgetInput {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else { throw CustomWidgetError.message("Could not create command output pipe.") }
        defer { for fd in descriptors where fd >= 0 { close(fd) } }
        _ = fcntl(descriptors[0], F_SETFL, O_NONBLOCK)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO)
        posix_spawn_file_actions_addchdir_np(&actions, NSHomeDirectory())
        // Own a process group so timeout and output-limit failures also stop shell children.
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        let inherited = ProcessInfo.processInfo.environment
        var environment = ["PATH": NSHomeDirectory() + "/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory()]
        for key in ["USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL"] { environment[key] = inherited[key] }
        let arguments = ([configuration.executable] + configuration.arguments).map { strdup($0) } + [nil]
        let variables = environment.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer { for pointer in arguments + variables { free(pointer) } }
        var pid: pid_t = 0
        let error = arguments.withUnsafeBufferPointer { argv in
            variables.withUnsafeBufferPointer { envp in
                posix_spawn(&pid, configuration.executable, &actions, &attributes, argv.baseAddress!, envp.baseAddress!)
            }
        }
        guard error == 0 else { throw CustomWidgetError.message("Could not start command: \(String(cString: strerror(error))). Check the executable path and permissions.") }
        close(descriptors[1]); descriptors[1] = -1
        var reaped = false
        defer {
            kill(-pid, SIGKILL)
            if !reaped {
                kill(pid, SIGKILL)
                var status: Int32 = 0
                while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
            }
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        var status: Int32 = 0
        var eof = false
        let deadline = ProcessInfo.processInfo.systemUptime + configuration.timeout
        while !reaped || !eof {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw CustomWidgetError.message("Command exceeded its \(Int(configuration.timeout))-second timeout.") }
            if !eof {
                let count = Darwin.read(descriptors[0], &buffer, buffer.count)
                if count > 0 {
                    guard data.count + count <= outputLimit else { throw CustomWidgetError.message("Command output exceeds the 64 KB limit.") }
                    data.append(contentsOf: buffer.prefix(count))
                } else if count == 0 { eof = true }
                else if errno != EAGAIN && errno != EINTR { throw CustomWidgetError.message("Could not read command output.") }
            }
            if !reaped {
                let result = waitpid(pid, &status, WNOHANG)
                if result == pid {
                    reaped = true
                    // A command must finish its work before exiting, not leave background children.
                    kill(-pid, SIGKILL)
                } else if result < 0 && errno != EINTR { throw CustomWidgetError.message("Could not read command exit status.") }
            }
            if !eof {
                var event = pollfd(fd: descriptors[0], events: Int16(POLLIN | POLLHUP), revents: 0)
                _ = poll(&event, 1, 20)
            } else if !reaped { _ = poll(nil, 0, 20) }
        }
        guard status == 0 else {
            let exitCode = (status >> 8) & 0xff
            throw CustomWidgetError.message("Command failed\(exitCode == 0 ? " or was stopped" : " with exit code \(exitCode)"). Run it in Terminal to check its authentication and diagnostics.")
        }
        guard let text = String(data: data, encoding: .utf8),
              (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else {
            throw CustomWidgetError.message("Command must print one UTF-8 JSON value to stdout. Send diagnostic messages to stderr.")
        }
        return CustomWidgetInput(text: text)
    }
}
#endif
