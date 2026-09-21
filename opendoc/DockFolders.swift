import Foundation

enum DockDropPlacement { case before, after, group }

extension DockStore {
    /// A running application becomes pinned only when a valid drop commits.
    func drop(_ item: DockItem, relativeTo targetID: UUID, placement: DockDropPlacement, in profileID: UUID) throws {
        guard item.id != targetID,
              var profile = archive.profiles.first(where: { $0.id == profileID }),
              let target = profile.items.first(where: { $0.id == targetID }) else { throw StoreError.invalidArchive }
        let item = profile.items.first(where: { $0.id == item.id }) ?? item
        if placement == .group {
            guard item.kind == .application else { throw StoreError.invalidArchive }
            if target.kind == .folder {
                try addApplications([item], into: targetID, in: profileID)
                return
            }
            guard target.kind == .application else { throw StoreError.invalidArchive }
            profile.items.removeAll { $0.id == item.id }
            guard let index = profile.items.firstIndex(where: { $0.id == targetID }) else { throw StoreError.invalidArchive }
            var folder = DockItem(kind: .folder, title: "Folder", symbol: "folder.fill")
            folder.children = [target, item]
            profile.items[index] = folder
        } else {
            guard profile.items.contains(where: { $0.id == item.id }) || item.kind == .application else { throw StoreError.invalidArchive }
            profile.items.removeAll { $0.id == item.id }
            guard let index = profile.items.firstIndex(where: { $0.id == targetID }) else { throw StoreError.invalidArchive }
            profile.items.insert(item, at: index + (placement == .after ? 1 : 0))
        }
        try update(profile)
    }

    func groupApplications(_ ids: Set<UUID>, in profileID: UUID, name: String) throws {
        guard var profile = archive.profiles.first(where: { $0.id == profileID }) else { return }
        let children = profile.items.filter { ids.contains($0.id) }
        guard children.count >= 2, children.count == ids.count, children.allSatisfy({ $0.kind == .application }),
              let insertion = profile.items.firstIndex(where: { ids.contains($0.id) }) else { throw StoreError.invalidArchive }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw StoreError.invalidName }
        var folder = DockItem(kind: .folder, title: title, symbol: "folder.fill")
        folder.children = children
        profile.items.removeAll { ids.contains($0.id) }
        profile.items.insert(folder, at: insertion)
        try update(profile)
    }

    /// Picker and drag additions share one transaction, preserving existing IDs.
    func addApplications(_ applications: [DockItem], into folderID: UUID, in profileID: UUID) throws {
        guard applications.allSatisfy({ $0.kind == .application }),
              var profile = archive.profiles.first(where: { $0.id == profileID }),
              let index = profile.items.firstIndex(where: { $0.id == folderID && $0.kind == .folder }) else {
            throw StoreError.invalidArchive
        }
        var children = profile.items[index].children ?? []
        for app in applications {
            let existing = profile.items.first { $0.kind == .application && $0.applicationURL == app.applicationURL }
            if !children.contains(where: { $0.id == app.id || (app.applicationURL != nil && $0.applicationURL == app.applicationURL) }) {
                children.append(existing ?? app)
            }
        }
        profile.items[index].children = children
        let urls = Set(children.compactMap(\.applicationURL))
        profile.items.removeAll { $0.kind == .application && $0.applicationURL.map(urls.contains) == true }
        try update(profile)
    }

    func ungroupFolder(_ id: UUID, in profileID: UUID) throws {
        guard var profile = archive.profiles.first(where: { $0.id == profileID }),
              let index = profile.items.firstIndex(where: { $0.id == id && $0.kind == .folder }) else { return }
        let children = profile.items.remove(at: index).children ?? []
        profile.items.insert(contentsOf: children, at: index)
        try update(profile)
    }

    func moveOutOfFolder(_ childID: UUID, folderID: UUID, in profileID: UUID) throws {
        guard var profile = archive.profiles.first(where: { $0.id == profileID }),
              let index = profile.items.firstIndex(where: { $0.id == folderID }),
              let child = profile.items[index].children?.first(where: { $0.id == childID }) else { return }
        profile.items[index].children?.removeAll { $0.id == childID }
        profile.items.insert(child, at: index + 1)
        try update(profile)
    }
}

extension DockItem {
    var applicationURL: URL? {
        guard kind == .application, let url, let parsed = URL(string: url), parsed.isFileURL else { return nil }
        return parsed.standardizedFileURL.resolvingSymlinksInPath()
    }
}
