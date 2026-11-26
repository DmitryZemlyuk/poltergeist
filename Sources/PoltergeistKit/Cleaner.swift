import Foundation

/// The last line of defence: decides whether a path may be deleted at all.
public struct SafetyGuard: Sendable {
    public let home: URL

    public init(home: URL = FS.home) {
        self.home = home
    }

    /// Folders that are never deleted themselves (only things inside them).
    public static let protectedRelative: Set<String> = [
        "", "Library", "Library/Caches", "Library/Logs", "Library/Application Support", "Library/Containers",
        "Library/Group Containers", "Library/Preferences", "Library/Developer", "Library/Developer/Xcode",
        "Library/Developer/CoreSimulator", "Library/Developer/CoreSimulator/Devices",
        "Library/Saved Application State", "Library/HTTPStorages", "Library/WebKit", "Library/LaunchAgents",
        "Library/Cookies", "Library/Application Scripts", "Library/iTunes", "Library/Android",
        "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Applications", "Public",
        ".Trash", ".npm", ".gradle", ".nvm", ".nvm/versions", ".nvm/versions/node", ".android", ".m2",
        ".ssh", ".config", ".local"
    ]

    /// Places never touched, not even inside.
    public static let forbiddenPrefixes: [String] = [
        "Library/Keychains", "Library/Mobile Documents", "Library/CloudStorage", "Library/Mail",
        "Library/Messages", "Library/Photos", "Library/Accounts", ".ssh", ".gnupg"
    ]

    static func resolved(_ url: URL) -> String {
        // Resolve the parent (e.g. /var → /private/var) but not the item itself: a symlink is deleted as a link.
        let parent = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
        return (parent == "/" ? "" : parent) + "/" + url.lastPathComponent
    }

    public func isAllowed(_ url: URL, mode: DeleteMode) -> Bool {
        let name = url.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !url.path.contains("/../") else { return false }
        let p = Self.resolved(url)
        let h = home.standardizedFileURL.resolvingSymlinksInPath().path
        if p.hasPrefix(h + "/") {
            let rel = String(p.dropFirst(h.count + 1))
            if Self.protectedRelative.contains(rel) { return false }
            for f in Self.forbiddenPrefixes where rel == f || rel.hasPrefix(f + "/") { return false }
            return true
        }
        // Apps outside home may only go to the Trash.
        if mode == .trash, p.hasPrefix("/Applications/"), p.hasSuffix(".app") {
            let inner = p.dropFirst("/Applications/".count)
            return inner.split(separator: "/").count <= 2
        }
        return false
    }
}

public struct CleanFailure: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var path: String
    public var reason: String
}

public struct CleanReport: Identifiable, Sendable {
    public let id = UUID()
    /// Space given back right away.
    public var freed: Int64 = 0
    /// Moved to the Trash (freed only once the Trash is emptied).
    public var trashed: Int64 = 0
    public var count = 0
    public var failures: [CleanFailure] = []
    public init() {}
}

public struct Cleaner {
    public var guardrail: SafetyGuard
    public var trash: (URL) throws -> Void
    public var simctl: (String) throws -> Void

    public init(guardrail: SafetyGuard = SafetyGuard(),
                trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
                simctl: @escaping (String) throws -> Void = { try Simulators.delete($0) }) {
        self.guardrail = guardrail
        self.trash = trash
        self.simctl = simctl
    }

    /// Deletes the given leaf items. Each path is checked by the guard first.
    public func clean(_ items: [CleanItem], cancel: CancelFlag? = nil, progress: ((Int, Int) -> Void)? = nil) -> CleanReport {
        var report = CleanReport()
        var seen = Set<String>()
        let fm = FileManager.default
        for (i, item) in items.enumerated() {
            if cancel?.isCancelled == true { break }
            progress?(i, items.count)
            if item.needsAccess { continue }
            switch item.mode {
            case .simulator:
                guard let udid = item.payload, seen.insert("sim:" + udid).inserted else { continue }
                do {
                    try simctl(udid)
                    report.freed += item.size
                    report.count += 1
                } catch {
                    report.failures.append(CleanFailure(path: "Simulator " + udid, reason: error.localizedDescription))
                }
            case .emptyTrash:
                for dir in item.urls {
                    guard let kids = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: []) else {
                        report.failures.append(CleanFailure(path: dir.path, reason: Self.noAccess))
                        continue
                    }
                    for k in kids {
                        remove(k, size: FS.size(of: k), mode: .remove, seen: &seen, report: &report)
                    }
                }
            case .remove, .trash:
                let single = item.urls.count == 1
                for u in item.urls {
                    remove(u, size: single ? item.size : FS.size(of: u), mode: item.mode, seen: &seen, report: &report)
                }
            }
        }
        progress?(items.count, items.count)
        return report
    }

    /// Reasons that start with "fail." are localization keys.
    public static let noAccess = "fail.noaccess"
    public static let protected = "fail.protected"

    private func remove(_ url: URL, size: Int64, mode: DeleteMode, seen: inout Set<String>, report: inout CleanReport) {
        let key = url.standardizedFileURL.path
        // Overlapping rows (same folder in two sections, or a folder and its parent) are handled once.
        guard seen.insert(key).inserted, !seen.contains(where: { key.hasPrefix($0 + "/") }) else { return }
        guard FS.exists(url) else { return }
        guard guardrail.isAllowed(url, mode: mode) else {
            report.failures.append(CleanFailure(path: url.path, reason: Self.protected))
            return
        }
        do {
            if mode == .trash {
                try trash(url)
                report.trashed += size
            } else {
                try FileManager.default.removeItem(at: url)
                report.freed += size
            }
            report.count += 1
        } catch {
            report.failures.append(CleanFailure(path: url.path, reason: error.localizedDescription))
        }
    }
}
