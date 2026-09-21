#if os(macOS)
import AppKit
import Darwin

@MainActor
final class NativeWidgetData {
    static let shared = NativeWidgetData()
    struct Reading: Equatable {
        var value: String
        var detail: String
        var isError = false
    }
    private struct CachedValue {
        var configuration: WebWidgetConfiguration
        var reading = Reading(value: "…", detail: "Connecting…")
        var nextRefresh = Date.distantPast
        var loading = false
    }
    private var cache: [UUID: CachedValue] = [:]
    private var requests = 0
    private var sampledAt = Date.distantPast
    private var lastCPU: (UInt32, UInt32)?
    private var cpu = Reading(value: "…", detail: "Sampling CPU…")
    private var memory = Reading(value: "…", detail: "Reading memory…")
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }()

    func reading(for item: DockItem) -> Reading {
        if item.widget == .webValue { return webReading(item) }
        sampleSystem()
        return item.widget == .cpu ? cpu : memory
    }

    func refresh(_ item: DockItem) {
        cache[item.id]?.nextRefresh = .distantPast
        _ = reading(for: item)
    }

    private func sampleSystem() {
        guard Date().timeIntervalSince(sampledAt) >= 1 else { return }
        sampledAt = Date()
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var load = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: load) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        if result == KERN_SUCCESS {
            let ticks = load.cpu_ticks
            let total = ticks.0 &+ ticks.1 &+ ticks.2 &+ ticks.3
            let idle = ticks.2
            if let previous = lastCPU {
                let elapsed = total &- previous.0
                let idleElapsed = idle &- previous.1
                let usage = elapsed > 0 ? max(0, min(100, 100 * (1 - Double(idleElapsed) / Double(elapsed)))) : 0
                cpu = Reading(value: "\(Int(usage.rounded()))%", detail: "CPU · \(ProcessInfo.processInfo.activeProcessorCount) cores")
            }
            lastCPU = (total, idle)
        }
        var vm = vm_statistics64_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout.size(ofValue: vm) / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(host, HOST_VM_INFO64, $0, &vmCount) }
        }
        if vmResult == KERN_SUCCESS {
            let used = (UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * UInt64(vm_kernel_page_size)
            let total = ProcessInfo.processInfo.physicalMemory
            let percent = Int(min(100, Double(used) / Double(max(1, total)) * 100))
            memory = Reading(value: "\(percent)%", detail: "\(ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .memory)) used")
        }
    }

    private func webReading(_ item: DockItem) -> Reading {
        guard let configuration = item.web else { return Reading(value: "Set up", detail: "Choose a JSON endpoint") }
        if cache[item.id]?.configuration != configuration { cache[item.id] = CachedValue(configuration: configuration) }
        guard let entry = cache[item.id] else { return Reading(value: "—", detail: "Unavailable") }
        if !entry.loading && entry.nextRefresh <= Date() && requests < 4 {
            cache[item.id]?.loading = true
            requests += 1
            Task { [weak self] in
                guard let self else { return }
                let result: Reading
                do {
                    try configuration.validate()
                    var request = URLRequest(url: URL(string: configuration.endpoint)!)
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    guard (200...299).contains(http.statusCode) else { throw WebValueError.http(http.statusCode) }
                    guard response.url?.scheme == "https" else { throw URLError(.secureConnectionFailed) }
                    var data = Data()
                    for try await byte in bytes {
                        guard data.count < 1_048_576 else { throw WebValueError.tooLarge }
                        data.append(byte)
                    }
                    result = Reading(value: try configuration.value(in: data), detail: "Updated \(Date().formatted(date: .omitted, time: .shortened))")
                } catch {
                    result = Reading(value: entry.reading.value == "…" ? "Unavailable" : entry.reading.value,
                                     detail: error.localizedDescription, isError: true)
                }
                requests -= 1
                guard cache[item.id]?.configuration == configuration else { return }
                cache[item.id]?.reading = result
                cache[item.id]?.loading = false
                cache[item.id]?.nextRefresh = Date().addingTimeInterval(configuration.refreshInterval)
            }
        }
        return entry.reading
    }
}
#endif
