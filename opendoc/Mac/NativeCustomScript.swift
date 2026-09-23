#if os(macOS)
import Foundation
import JavaScriptCore
import Darwin

/// User JavaScript runs in a short-lived process, never on the dock's main thread.
/// Only JSON state and extracted text cross the boundary; no native objects are exposed.
enum NativeCustomScript {
    nonisolated struct Request: Codable, Sendable {
        var script: String
        var state: [String: Double]
        var input: CustomWidgetInput
        var action: Bool
    }
    nonisolated struct Response: Codable, Sendable {
        var output: CustomWidgetOutput?
        var state: [String: Double]?
        var error: String?
    }
    private static let queue = DispatchQueue(label: "OpenDoc.CustomScript", qos: .utility)

    static func run(_ request: Request) async throws -> Response {
        guard let executable = Bundle.main.executableURL else { throw CustomWidgetError.message("The script worker is unavailable.") }
        let data = try JSONEncoder().encode(request)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let process = Process()
                    let input = Pipe(); let output = Pipe()
                    process.executableURL = executable
                    process.arguments = ["--custom-widget-script"]
                    process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
                    try process.run()
                    try input.fileHandleForWriting.write(contentsOf: data)
                    try input.fileHandleForWriting.close()
                    let result = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0, !result.isEmpty, result.count <= 16_384 else {
                        throw CustomWidgetError.message("The script stopped or exceeded its 2-second limit. Check for loops or excessive memory use.")
                    }
                    let response = try JSONDecoder().decode(Response.self, from: result)
                    if let error = response.error { throw CustomWidgetError.message(error) }
                    continuation.resume(returning: response)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    nonisolated static func runWorker() {
        // An infinite loop terminates only this worker, including if the app exits.
        alarm(2)
        var memoryLimit = rlimit(rlim_cur: 256 * 1024 * 1024, rlim_max: 256 * 1024 * 1024)
        _ = setrlimit(RLIMIT_DATA, &memoryLimit)
        let response: Response
        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard data.count <= 1_048_576 else { throw CustomWidgetError.message("Script input is too large.") }
            response = try evaluate(JSONDecoder().decode(Request.self, from: data))
        } catch { response = Response(error: String(error.localizedDescription.prefix(600))) }
        if let data = try? JSONEncoder().encode(response) { FileHandle.standardOutput.write(data) }
    }

    nonisolated static func evaluate(_ request: Request) throws -> Response {
        guard request.script.utf8.count <= 16_384, CustomWidgetConfiguration.validState(request.state),
              let context = JSContext() else { throw CustomWidgetError.message("Invalid script or state.") }
        let function = context.evaluateScript("(function(state, input) { 'use strict';\n" + request.script + "\n})")
        let input: [String: Any] = ["text": request.input.text, "matches": request.input.matches]
        let result = function?.call(withArguments: [request.state, input])
        if let exception = context.exception { throw CustomWidgetError.message(String((exception.toString() ?? "JavaScript error").prefix(600))) }
        guard let object = result?.toDictionary() as? [String: Any] else {
            throw CustomWidgetError.message(request.action ? "Return the state object from a button action." : "Return an object with value, detail, and optional progress.")
        }
        if request.action {
            var state: [String: Double] = [:]
            for (key, value) in object {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
                    throw CustomWidgetError.message("State values must be numbers.")
                }
                state[key] = number.doubleValue
            }
            guard CustomWidgetConfiguration.validState(state) else { throw CustomWidgetError.message("State exceeds its size or numeric limits.") }
            return Response(state: state)
        }
        guard let value = object["value"], value is String || value is NSNumber else {
            throw CustomWidgetError.message("The render function must return a text or number value.")
        }
        let text = value as? String ?? (value as? NSNumber)?.stringValue ?? ""
        let progress = (object["progress"] as? NSNumber)?.doubleValue
        guard progress?.isFinite != false else { throw CustomWidgetError.message("Progress must be a finite number between 0 and 1.") }
        return Response(output: CustomWidgetOutput(value: String(text.prefix(160)), detail: String((object["detail"] as? String ?? "").prefix(160)),
                                                  progress: progress.map { min(1, max(0, $0)) }))
    }
}
#endif
