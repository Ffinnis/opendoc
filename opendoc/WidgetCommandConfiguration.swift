import Foundation

struct WidgetCommandConfiguration: Codable, Equatable, Sendable {
    var enabled = false
    var executable = ""
    var arguments: [String] = []
    var timeout: TimeInterval = 20

    nonisolated func validate(requireExecutable: Bool = true) throws {
        guard executable.utf8.count <= 4096, !executable.contains("\0"),
              arguments.count <= 32, arguments.allSatisfy({ !$0.contains("\0") && $0.utf8.count <= 4096 }),
              arguments.reduce(0, { $0 + $1.utf8.count }) <= 16_384,
              timeout.isFinite, (1...25).contains(timeout) else {
            throw CustomWidgetError.message("Use up to 32 arguments totaling 16 KB and a command timeout of 1–25 seconds.")
        }
        if requireExecutable && !executable.hasPrefix("/") {
            throw CustomWidgetError.message("Choose an absolute executable path, such as /bin/bash or /opt/homebrew/bin/node.")
        }
    }
}
