import Foundation

/// Text that the app shows. Scanners don't know the UI language, so they hand over
/// either a localization key (with string arguments for `%@`) or a raw name from the disk.
public enum Phrase: Hashable, Sendable {
    case key(String, [String] = [])
    case raw(String)
}

public enum Tint: String, Hashable, Sendable {
    case blue, teal, indigo, green, orange, red, gray, purple, pink, yellow, mint, brown
}

public enum DeleteMode: String, Hashable, Sendable {
    /// Deleted right away. Only for things that come back on their own (caches, logs, build products).
    case remove
    /// Moved to the Trash.
    case trash
    /// Permanently removes what is already in the Trash.
    case emptyTrash
    /// `xcrun simctl delete <udid>` (payload = udid).
    case simulator
}

public struct CleanItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: Phrase
    public var subtitle: Phrase?
    /// SF Symbol name, or "ghost" for the app's own ghost glyph.
    public var symbol: String
    public var tint: Tint
    public var urls: [URL]
    public var size: Int64
    public var mode: DeleteMode
    public var checkedByDefault: Bool
    /// The item exists but can't be read without Full Disk Access.
    public var needsAccess: Bool
    /// Shown instead of the subtitle, in orange.
    public var warning: Phrase?
    public var payload: String?
    public var children: [CleanItem]

    public init(id: String, title: Phrase, subtitle: Phrase? = nil, symbol: String, tint: Tint,
                urls: [URL], size: Int64, mode: DeleteMode, checkedByDefault: Bool = true,
                needsAccess: Bool = false, warning: Phrase? = nil, payload: String? = nil,
                children: [CleanItem] = []) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.urls = urls
        self.size = size
        self.mode = mode
        self.checkedByDefault = checkedByDefault
        self.needsAccess = needsAccess
        self.warning = warning
        self.payload = payload
        self.children = children
    }

    /// The things that actually get deleted: the item itself or, for a parent, all of its children.
    public var leaves: [CleanItem] {
        children.isEmpty ? [self] : children.flatMap { $0.leaves }
    }

    /// A parent row made of child rows. Returns nil when there is nothing inside.
    public static func parent(id: String, title: Phrase, subtitle: Phrase? = nil, symbol: String, tint: Tint,
                              mode: DeleteMode, children: [CleanItem]) -> CleanItem? {
        let kids = children.filter { $0.size > 0 || $0.needsAccess }.sorted { $0.size > $1.size }
        guard !kids.isEmpty else { return nil }
        if kids.count == 1, var only = kids.first, only.children.isEmpty {
            // One child: show it as the row itself, keeping the parent's look.
            only.id = id + "|" + only.id
            let childName = only.title
            only.title = title
            only.subtitle = subtitle ?? (childName == title ? nil : childName)
            only.symbol = symbol
            only.tint = tint
            return only
        }
        return CleanItem(id: id, title: title,
                         subtitle: subtitle ?? .key("item.count", [String(kids.count)]),
                         symbol: symbol, tint: tint, urls: kids.flatMap { $0.urls },
                         size: kids.reduce(0) { $0 + $1.size }, mode: mode,
                         checkedByDefault: kids.contains { $0.checkedByDefault },
                         needsAccess: kids.allSatisfy { $0.needsAccess },
                         children: kids)
    }
}

public struct CleanGroup: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: Phrase
    public var items: [CleanItem]

    public init(id: String, title: Phrase, items: [CleanItem]) {
        self.id = id
        self.title = title
        self.items = items.sorted { $0.size > $1.size }
    }

    public var size: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// What a scan may look at.
public struct ScanContext: Sendable {
    public var home: URL
    public var runningBundleIDs: Set<String>
    public var fullDiskAccess: Bool
    public var oldDownloadsDays: Int
    public var oldProjectsDays: Int
    public var now: Date
    /// Folders with installed apps (used to tell leftovers from live data).
    public var appFolders: [URL]

    public init(home: URL = FS.home, runningBundleIDs: Set<String> = [], fullDiskAccess: Bool = false,
                oldDownloadsDays: Int = 90, oldProjectsDays: Int = 90, now: Date = Date(),
                appFolders: [URL] = InstalledApps.allFolders) {
        self.home = home
        self.runningBundleIDs = Set(runningBundleIDs.map { $0.lowercased() })
        self.fullDiskAccess = fullDiskAccess
        self.oldDownloadsDays = oldDownloadsDays
        self.oldProjectsDays = oldProjectsDays
        self.now = now
        self.appFolders = appFolders
    }

    public func url(_ relative: String) -> URL {
        home.appendingPathComponent(relative)
    }
}

/// Thread-safe "stop" switch for long scans.
public final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public func cancel() { lock.lock(); value = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
