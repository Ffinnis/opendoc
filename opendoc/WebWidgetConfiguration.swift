import Foundation
import CoreFoundation

struct WebWidgetConfiguration: Codable, Equatable {
    var endpoint = ""
    var keyPath = ""
    var suffix = ""
    var refreshInterval: TimeInterval = 300

    func validate() throws {
        guard let url = URL(string: endpoint), url.scheme == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil, endpoint.count <= 4096, keyPath.count <= 256,
              suffix.count <= 32, refreshInterval.isFinite, (60...3600).contains(refreshInterval) else {
            throw StoreError.invalidArchive
        }
    }

    func value(in data: Data) throws -> String {
        guard data.count <= 1_048_576 else { throw WebValueError.tooLarge }
        var value: Any = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        if !keyPath.isEmpty {
            for part in keyPath.split(separator: ".", omittingEmptySubsequences: false) {
                if let object = value as? [String: Any], let next = object[String(part)] { value = next }
                else if let array = value as? [Any], let index = Int(part), array.indices.contains(index) { value = array[index] }
                else { throw WebValueError.missingField }
            }
        }
        let text: String
        if let string = value as? String { text = string }
        else if let number = value as? NSNumber { text = CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue }
        else { throw WebValueError.notScalar }
        return String(text.prefix(160)) + suffix
    }
}

enum WebValueError: LocalizedError {
    case tooLarge, missingField, notScalar, http(Int)
    var errorDescription: String? {
        switch self {
        case .tooLarge: "The response exceeds 1 MB."
        case .missingField: "The JSON field was not found. Check its path."
        case .notScalar: "Select a text or number field, rather than an object or list."
        case .http(let status): "The server returned HTTP \(status)."
        }
    }
}
