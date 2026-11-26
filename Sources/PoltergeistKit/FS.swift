import Foundation

public enum FS {
    static let fm = FileManager.default

    public static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static let sizeKeys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

    public static func exists(_ url: URL) -> Bool {
        // lstat: a dangling symlink still "exists" for deleting purposes.
        (try? fm.attributesOfItem(atPath: url.path)) != nil
    }

    public static func isDirectory(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return v?.isDirectory == true && v?.isSymbolicLink != true
    }

    /// Direct children, including hidden ones, without ".DS_Store". Empty when unreadable.
    public static func children(_ url: URL) -> [URL] {
        ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: sizeKeys, options: [])) ?? [])
            .filter { $0.lastPathComponent != ".DS_Store" }
    }

    /// True when the folder exists and its contents can be listed (no privacy block).
    public static func canList(_ url: URL) -> Bool {
        (try? fm.contentsOfDirectory(atPath: url.path)) != nil
    }

    /// Space taken on disk (allocated size), recursive, without following symlinks.
    public static func size(of url: URL, cancel: CancelFlag? = nil) -> Int64 {
        guard let v = try? url.resourceValues(forKeys: Set(sizeKeys)) else { return 0 }
        if v.isSymbolicLink == true { return 0 }
        if v.isDirectory != true {
            return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: sizeKeys, options: [],
                                    errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        var n = 0
        for case let f as URL in e {
            n += 1
            if n % 4096 == 0, cancel?.isCancelled == true { break }
            guard let fv = try? f.resourceValues(forKeys: Set(sizeKeys)) else { continue }
            if fv.isDirectory == true || fv.isSymbolicLink == true { continue }
            total += Int64(fv.totalFileAllocatedSize ?? fv.fileAllocatedSize ?? 0)
        }
        return total
    }

    public static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// When the file landed in its folder (Downloads), falling back to creation date.
    public static func added(_ url: URL) -> Date? {
        let v = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return v?.addedToDirectoryDate ?? v?.creationDate
    }

    /// "~/Library/Caches" style path for display.
    public static func tilde(_ url: URL, home: URL = FS.home) -> String {
        let p = url.path, h = home.path
        if p == h { return "~" }
        if p.hasPrefix(h + "/") { return "~" + p.dropFirst(h.count) }
        return p
    }

    /// Children turned into rows, biggest first. Empty folders are skipped.
    static func childItems(of dir: URL, idPrefix: String, symbol: String, tint: Tint, mode: DeleteMode,
                           home: URL, cancel: CancelFlag? = nil,
                           include: (URL) -> Bool = { _ in true },
                           title: (URL) -> Phrase = { .raw($0.lastPathComponent) },
                           subtitle: (URL) -> Phrase? = { _ in nil },
                           checked: (URL) -> Bool = { _ in true },
                           warning: (URL) -> Phrase? = { _ in nil }) -> [CleanItem] {
        var items: [CleanItem] = []
        for u in children(dir) where include(u) {
            if cancel?.isCancelled == true { break }
            let s = size(of: u, cancel: cancel)
            guard s > 0 else { continue }
            items.append(CleanItem(id: idPrefix + u.path, title: title(u), subtitle: subtitle(u),
                                   symbol: symbol, tint: tint, urls: [u], size: s, mode: mode,
                                   checkedByDefault: checked(u), warning: warning(u)))
        }
        return items.sorted { $0.size > $1.size }
    }

    /// A single folder as one row (nil when missing or empty). Unreadable folders become "needs access" rows.
    static func folderItem(_ url: URL, id: String, title: Phrase, subtitle: Phrase? = nil, symbol: String,
                           tint: Tint, mode: DeleteMode, checked: Bool = true, home: URL,
                           cancel: CancelFlag? = nil) -> CleanItem? {
        guard exists(url) else { return nil }
        if isDirectory(url) && !canList(url) {
            return CleanItem(id: id, title: title, subtitle: subtitle ?? .raw(tilde(url, home: home)),
                             symbol: symbol, tint: tint, urls: [url], size: 0, mode: mode,
                             checkedByDefault: false, needsAccess: true)
        }
        let s = size(of: url, cancel: cancel)
        guard s > 0 else { return nil }
        return CleanItem(id: id, title: title, subtitle: subtitle ?? .raw(tilde(url, home: home)),
                         symbol: symbol, tint: tint, urls: [url], size: s, mode: mode, checkedByDefault: checked)
    }
}

public struct VolumeInfo: Hashable, Sendable {
    public var name: String
    public var total: Int64
    public var available: Int64

    public static func forHome() -> VolumeInfo? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                         .volumeAvailableCapacityKey, .volumeLocalizedNameKey]
        guard let v = try? FS.home.resourceValues(forKeys: keys), let total = v.volumeTotalCapacity else { return nil }
        let avail = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
        return VolumeInfo(name: v.volumeLocalizedName ?? "Macintosh HD", total: Int64(total), available: avail)
    }
}

public enum FullDiskAccess {
    /// Whether the app may read privacy-protected places (Trash, Mail, other apps' containers).
    public static var isGranted: Bool {
        if let h = FileHandle(forReadingAtPath: "/Library/Application Support/com.apple.TCC/TCC.db") {
            try? h.close()
            return true
        }
        return FS.canList(FS.home.appendingPathComponent("Library/Safari"))
    }
}
