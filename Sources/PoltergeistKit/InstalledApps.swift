import Foundation
import CoreServices

public struct AppInfo: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public var url: URL
    public var name: String
    public var bundleID: String?
    public var version: String?
    public var lastUsed: Date?

    public var isApple: Bool { bundleID?.lowercased().hasPrefix("com.apple.") == true }
}

public enum InstalledApps {
    /// Folders where the user's own apps live (shown in "Apps").
    public static var userFolders: [URL] {
        [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/Applications/Utilities"),
         FS.home.appendingPathComponent("Applications")]
    }

    /// Every folder with apps, system ones too (used to recognise data that still has an owner).
    public static var allFolders: [URL] {
        userFolders + ["/System/Applications", "/System/Applications/Utilities", "/System/Library/CoreServices",
                       "/System/Library/CoreServices/Applications", "/Library/Application Support",
                       "/Library/PreferencePanes", FS.home.appendingPathComponent("Library/PreferencePanes").path]
            .map { URL(fileURLWithPath: $0) }
    }

    static func bundles(in folder: URL, depth: Int) -> [URL] {
        var out: [URL] = []
        for u in FS.children(folder) {
            let ext = u.pathExtension.lowercased()
            if ext == "app" || ext == "prefpane" {
                out.append(u)
            } else if depth > 0, ext.isEmpty, FS.isDirectory(u) {
                out += bundles(in: u, depth: depth - 1)
            }
        }
        return out
    }

    public static func info(_ url: URL) -> AppInfo {
        let b = Bundle(url: url)
        let dict = b?.infoDictionary ?? [:]
        let name = (dict["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        var last: Date?
        if let item = MDItemCreateWithURL(nil, url as CFURL) {
            last = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        }
        return AppInfo(url: url, name: name, bundleID: b?.bundleIdentifier,
                       version: dict["CFBundleShortVersionString"] as? String, lastUsed: last)
    }

    /// The user's apps, without Apple's own.
    public static func list(folders: [URL] = userFolders) -> [AppInfo] {
        var seen = Set<String>()
        var out: [AppInfo] = []
        for f in folders {
            for u in bundles(in: f, depth: 1) where u.pathExtension.lowercased() == "app" {
                let p = u.resolvingSymlinksInPath().path
                guard seen.insert(p).inserted else { continue }
                let a = info(u)
                if !a.isApple { out.append(a) }
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Bundle ids (lowercased) of everything installed, including helpers and extensions inside apps.
    public static func knownBundleIDs(folders: [URL]) -> (ids: Set<String>, names: [String: String]) {
        var ids = Set<String>()
        var names: [String: String] = [:]
        for f in folders {
            for app in bundles(in: f, depth: 2) {
                guard let b = Bundle(url: app), let id = b.bundleIdentifier?.lowercased() else { continue }
                ids.insert(id)
                if names[id] == nil {
                    names[id] = (b.infoDictionary?["CFBundleDisplayName"] as? String)
                        ?? (b.infoDictionary?["CFBundleName"] as? String)
                        ?? app.deletingPathExtension().lastPathComponent
                }
                for sub in ["Contents/PlugIns", "Contents/Library/LoginItems", "Contents/XPCServices",
                            "Contents/Library/LaunchServices", "Contents/Helpers", "Contents/Library/Helpers",
                            "Contents/Extensions", "Contents/Library/SystemExtensions"] {
                    for inner in FS.children(app.appendingPathComponent(sub)) {
                        if let iid = Bundle(url: inner)?.bundleIdentifier?.lowercased() { ids.insert(iid) }
                    }
                }
            }
        }
        return (ids, names)
    }
}

/// Files an app keeps outside its bundle (offered when the app is uninstalled).
public enum AppFiles {
    public static func related(to app: AppInfo, _ c: ScanContext) -> [CleanItem] {
        guard let bid = app.bundleID?.lowercased(), !bid.isEmpty, !app.isApple else { return [] }
        let name = app.name.lowercased()
        var places = ["Library/Application Support", "Library/Caches", "Library/Preferences",
                      "Library/Preferences/ByHost", "Library/Saved Application State", "Library/HTTPStorages",
                      "Library/WebKit", "Library/Logs", "Library/LaunchAgents", "Library/Cookies"]
        if c.fullDiskAccess {
            places += ["Library/Containers", "Library/Group Containers", "Library/Application Scripts"]
        }
        var out: [CleanItem] = []
        for p in places {
            for u in FS.children(c.url(p)) {
                let file = u.lastPathComponent
                let lower = file.lowercased()
                var match = false
                if let id = LeftoversScanner.bundleID(fromName: file), id == bid || id.hasPrefix(bid + ".") { match = true }
                // ByHost files look like "com.vendor.app.<hardware-uuid>.plist".
                if p.hasSuffix("ByHost"), lower.hasPrefix(bid + ".") { match = true }
                if name.count >= 4, lower == name || lower == name + ".plist" { match = true }
                guard match else { continue }
                out.append(CleanItem(id: "rel:" + u.path, title: .raw(p.replacingOccurrences(of: "Library/", with: "")),
                                     subtitle: .raw(file), symbol: "doc", tint: .gray, urls: [u],
                                     size: FS.size(of: u), mode: .trash))
            }
        }
        return out.sorted { $0.size > $1.size }
    }
}
