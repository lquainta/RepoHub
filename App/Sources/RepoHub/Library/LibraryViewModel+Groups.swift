import Foundation

extension LibraryViewModel {
    /// Creates a group and optionally adds repositories to it.
    ///
    /// - Returns: Whether the group was created; on failure ``errorMessage`` explains why.
    @discardableResult
    func createGroup(named name: String, adding paths: [String] = []) -> Bool {
        do {
            let group = try store.createGroup(named: name)
            if !paths.isEmpty {
                try store.add(paths, to: group)
            }
            load()
            return true
        } catch {
            report(error, message: error.localizedDescription)
            return false
        }
    }

    /// Renames the group named `name`, keeping it selected if it was.
    func renameGroup(_ name: String, to newName: String) {
        guard let group = groups.first(where: { $0.name == name }) else {
            return
        }
        do {
            try store.rename(group, to: newName)
            if scope == .group(name) {
                scope = .group(group.name)
            }
        } catch {
            report(error, message: error.localizedDescription)
        }
        load()
    }

    /// Deletes the group named `name`. Its repositories stay tracked.
    func deleteGroup(_ name: String) {
        guard let group = groups.first(where: { $0.name == name }) else {
            return
        }
        do {
            try store.deleteGroup(group)
            if scope == .group(name) {
                scope = .all
            }
        } catch {
            report(error, message: String(localized: "Couldn't delete the group \(name)."))
        }
        load()
    }

    /// Adds the repositories at `paths` to the group named `name`.
    func add(_ paths: [String], toGroup name: String) {
        guard let group = groups.first(where: { $0.name == name }) else {
            return
        }
        do {
            try store.add(paths, to: group)
        } catch {
            report(error, message: String(localized: "Couldn't add to the group \(name)."))
        }
        load()
    }

    /// Removes the repositories at `paths` from the group named `name`.
    func remove(_ paths: [String], fromGroup name: String) {
        guard let group = groups.first(where: { $0.name == name }) else {
            return
        }
        do {
            try store.remove(paths, from: group)
        } catch {
            report(error, message: String(localized: "Couldn't remove from the group \(name)."))
        }
        load()
    }

    /// The names of the groups containing the repository at `path`.
    func groupNames(containing path: String) -> [String] {
        groups.filter { $0.repositories.contains { $0.path == path } }.map(\.name)
    }
}
