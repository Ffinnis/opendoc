#if os(macOS)
import Foundation

enum NativeWindowSupport {
    private struct Cached {
        let modified: Date?
        let command: String?
    }
    private static var cache: [URL: Cached] = [:]
    private static let standardURL = URL(fileURLWithPath: "/System/Library/ScriptingDefinitions/CocoaStandard.sdef")

    static func command(for applicationURL: URL) -> String? {
        guard let bundle = Bundle(url: applicationURL),
              let filename = bundle.object(forInfoDictionaryKey: "OSAScriptingDefinition") as? String,
              let resources = bundle.resourceURL else { return nil }
        let url = resources.appendingPathComponent(filename).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(resources.resolvingSymlinksInPath().path + "/") else { return nil }
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let cached = cache[url], cached.modified == modified { return cached.command }
        let command = readDictionary(url).flatMap { Self.command(in: $0, standard: readDictionary(standardURL)) }
        if cache.count >= 128 { cache.removeAll() }
        cache[url] = Cached(modified: modified, command: command)
        return command
    }

    private static func readDictionary(_ url: URL) -> Data? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 2_000_000 else { return nil }
        return try? Data(contentsOf: url)
    }

    static func command(in data: Data, standard: Data? = nil) -> String? {
        guard data.count <= 2_000_000,
              let document = try? XMLDocument(data: data, options: .nodeLoadExternalEntitiesNever) else { return nil }
        var documents = [document]
        // Resolve only Apple's standard dictionary. Never load arbitrary XML
        // entities, remote imports, or paths declared by another application.
        let includes = (try? document.nodes(forXPath: "//*[local-name()='include']")) ?? []
        if includes.contains(where: { ($0 as? XMLElement)?.attribute(forName: "href")?.stringValue == standardURL.absoluteString }),
           let standard, standard.count <= 2_000_000,
           let imported = try? XMLDocument(data: standard, options: .nodeLoadExternalEntitiesNever) {
            documents.insert(imported, at: 0)
        }
        func elements(_ path: String) -> [XMLElement] {
            documents.flatMap { (try? $0.nodes(forXPath: path)) ?? [] }.compactMap { $0 as? XMLElement }
        }
        guard elements("//command").contains(where: { $0.attribute(forName: "code")?.stringValue == "corecrel" && $0.attribute(forName: "hidden")?.stringValue != "yes" }) else { return nil }
        let classes = elements("//class")
        let applicationNames = Set(classes.filter { $0.attribute(forName: "code")?.stringValue == "capp" }.compactMap { $0.attribute(forName: "name")?.stringValue })
        var writable: [String: Bool] = [:]
        for owner in elements("//class | //class-extension") {
            let name = owner.attribute(forName: owner.name == "class" ? "name" : "extends")?.stringValue ?? ""
            guard applicationNames.contains(name) else { continue }
            for element in owner.elements(forName: "element") {
                guard let type = element.attribute(forName: "type")?.stringValue else { continue }
                writable[type] = element.attribute(forName: "access")?.stringValue != "r" && element.attribute(forName: "hidden")?.stringValue != "yes"
            }
        }
        let candidates = classes.filter {
            writable[$0.attribute(forName: "name")?.stringValue ?? ""] == true && $0.attribute(forName: "hidden")?.stringValue != "yes"
        }
        let windowNames = Set(classes.filter { $0.attribute(forName: "code")?.stringValue == "cwin" }.compactMap { $0.attribute(forName: "name")?.stringValue })
        let window = candidates.first { $0.attribute(forName: "code")?.stringValue == "brow" }
            ?? candidates.first { $0.attribute(forName: "code")?.stringValue == "cwin" || $0.attribute(forName: "name")?.stringValue?.lowercased() == "window" }
            ?? candidates.first { windowNames.contains($0.attribute(forName: "inherits")?.stringValue ?? "") }
        let target = window ?? candidates.first { $0.attribute(forName: "code")?.stringValue == "docu" }
        guard let code = target?.attribute(forName: "code")?.stringValue,
              code.utf8.count == 4, code.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { return nil }
        // Raw class codes keep dictionary-provided names out of executable text.
        return "make new «class \(code)»"
    }
}
#endif
