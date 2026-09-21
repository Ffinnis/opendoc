#if os(macOS)
import Foundation
import Darwin

nonisolated enum AgentTransport {
    static let limit = 16 * 1024 * 1024
    static var directory: String { "/tmp/opendoc-agent-\(getuid())" }
    static var path: String { directory + "/control.sock" }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "OpenDoc.Agent", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func address() -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            bytes.copyBytes(from: path.utf8CString.map { UInt8(bitPattern: $0) })
        }
        return address
    }

    static func configure(_ fd: Int32) {
        var timeout = timeval(tv_sec: 35, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }

    static func sameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0; var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }

    static func read(_ fd: Int32, maximum: Int) throws -> Data {
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 { return data }
            if count < 0 {
                if errno == EINTR { continue }
                throw failure("Agent connection timed out or closed. Read state before retrying a mutation.")
            }
            guard data.count + count <= maximum else { throw failure("Agent message exceeds its size limit.") }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    static func write(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw failure("Could not write the agent response.") }
                offset += count
            }
        }
    }

    static func request(_ data: Data) throws -> Data {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw failure("Could not create the local agent connection.") }
        defer { close(fd) }
        configure(fd)
        var address = address()
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw failure("Open Doc is not running with agent support. Launch the current app build first.") }
        guard sameUser(fd) else { throw failure("The agent service belongs to another user.") }
        try write(data, to: fd)
        shutdown(fd, SHUT_WR)
        return try read(fd, maximum: limit)
    }
}

/// One serial connection at a time; socket I/O never runs on the UI thread.
nonisolated final class NativeAgentServer: @unchecked Sendable {
    private let source: DispatchSourceRead
    private let handler: @MainActor @Sendable (Data) async -> Data

    init(handler: @escaping @MainActor @Sendable (Data) async -> Data) throws {
        self.handler = handler
        let directory = AgentTransport.directory
        if mkdir(directory, 0o700) != 0 && errno != EEXIST { throw AgentTransport.failure("Could not create the agent socket directory.") }
        var info = stat()
        guard lstat(directory, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o077 == 0 else {
            throw AgentTransport.failure("The agent socket directory must be private and owned by the current user.")
        }
        let lock = open(directory + "/service.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw AgentTransport.failure("Could not open the agent service lock.") }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { close(lock); throw AgentTransport.failure("Another Open Doc instance owns the agent service.") }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { close(lock); throw AgentTransport.failure("Could not create the agent socket.") }
        AgentTransport.configure(fd)
        unlink(AgentTransport.path)
        var address = AgentTransport.address()
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(AgentTransport.path, 0o600) == 0, listen(fd, 4) == 0 else {
            close(fd); unlink(AgentTransport.path); close(lock)
            throw AgentTransport.failure("Could not listen on the agent socket.")
        }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let queue = DispatchQueue(label: "OpenDoc.AgentSocket", qos: .utility)
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            defer { close(client) }
            guard let self, AgentTransport.sameUser(client) else { return }
            _ = fcntl(client, F_SETFL, 0)
            AgentTransport.configure(client)
            do {
                let data = try AgentTransport.read(client, maximum: 1_048_576)
                let reply = Reply()
                Task { @MainActor in
                    reply.data = await self.handler(data)
                    reply.ready.signal()
                }
                reply.ready.wait()
                try AgentTransport.write(reply.data, to: client)
            } catch {
                let result: [String: Any] = ["ok": false, "error": error.localizedDescription]
                if let data = try? JSONSerialization.data(withJSONObject: result) { try? AgentTransport.write(data, to: client) }
            }
        }
        source.setCancelHandler { close(fd); unlink(AgentTransport.path); close(lock) }
        source.resume()
    }

    func stop() { source.cancel() }
    deinit { source.cancel() }
    private final class Reply: @unchecked Sendable {
        let ready = DispatchSemaphore(value: 0)
        var data = Data()
    }
}
#endif
