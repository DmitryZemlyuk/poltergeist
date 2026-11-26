import Foundation

/// Finds data left behind by apps that are no longer installed.
public enum LeftoversScanner {
    /// Where apps keep their data, and how the entries are named there.
    static let places: [(rel: String, needsAccess: Bool)] = [
        ("Library/Application Support", false), ("Library/Caches", false), ("Library/Preferences", false),
        ("Library/Saved Application State", false), ("Library/HTTPStorages", false), ("Library/WebKit", false),
        ("Library/Logs", false), ("Library/LaunchAgents", false), ("Library/Cookies", false),
        ("Library/Application Scripts", true), ("Library/Containers", true), ("Library/Group Containers", true)
    ]

    /// Never treated as leftovers: the system's own data and well-known non-app owners.
    static let systemPrefixes = [
        "com.apple.", "apple.", "systemgroup.", "group.com.apple.", "org.cups.", "edu.mit.", "com.openssh.",
        "org.openssh.", "io.github.dmitryzemlyuk.", "com.microsoft.office.licensing", "org.python.", "net.mullvad.daemon"
    ]

    static let topLevelDomains: Set<String> = [
        "com", "org", "net", "io", "de", "ru", "ua", "me", "co", "app", "dev", "jp", "uk", "fr", "us", "info",
        "tv", "cc", "ch", "nl", "se", "it", "pl", "ca", "au", "at", "be", "cz", "dk", "fi", "es", "pt", "br",
        "cn", "kr", "in", "eu", "is", "sh", "ai", "so", "fm", "im", "ly", "to", "gg", "xyz", "pro", "studio"
    ]

    /// Turns a folder/file name into a bundle id (lowercased), or nil when it doesn't look like one.
    public static func bundleID(fromName name: String) -> String? {
        var n = name
        for suffix in [".plist", ".savedState", ".binarycookies", ".savedstate"] where n.hasSuffix(suffix) {
            n.removeLast(suffix.count)
        }
        // Team-id prefix of group containers: "UBF8T346G9.com.vendor.shared"
        let parts = n.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var labels = parts
        if let first = labels.first, first.count == 10,
           first.allSatisfy({ ($0.isUppercase || $0.isNumber) && $0.isASCII }) {
            labels.removeFirst()
        }
        if labels.first?.lowercased() == "group" { labels.removeFirst() }
        guard labels.count >= 3, labels.allSatisfy({ !$0.isEmpty }),
              let tld = labels.first?.lowercased(), topLevelDomains.contains(tld) else { return nil }
        guard labels.allSatisfy({ $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }) else { return nil }
        return labels.joined(separator: ".").lowercased()
    }

    static func vendor(_ id: String) -> String {
        id.split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// True when some installed app (or a helper from the same vendor) still owns this id.
    public static func isOwned(_ id: String, installed: Set<String>, vendors: Set<String>) -> Bool {
        if installed.contains(id) || vendors.contains(vendor(id)) { return true }
        for i in installed where id.hasPrefix(i + ".") || i.hasPrefix(id + ".") { return true }
        return false
    }

    public static func isSystem(_ id: String) -> Bool {
        systemPrefixes.contains { id.hasPrefix($0) || id + "." == $0 }
    }

    public static func scan(_ c: ScanContext, cancel: CancelFlag?) -> [CleanGroup] {
        let known = InstalledApps.knownBundleIDs(folders: c.appFolders)
        let installed = known.ids.union(c.runningBundleIDs)
        let vendors = Set(installed.map(vendor))

        var found: [String: [(place: String, url: URL)]] = [:]
        for place in places {
            if place.needsAccess && !c.fullDiskAccess { continue }
            for u in FS.children(c.url(place.rel)) {
                guard let id = bundleID(fromName: u.lastPathComponent), !isSystem(id),
                      !isOwned(id, installed: installed, vendors: vendors) else { continue }
                found[id, default: []].append((place.rel.replacingOccurrences(of: "Library/", with: ""), u))
            }
        }

        var items: [CleanItem] = []
        for (id, hits) in found {
            if cancel?.isCancelled == true { break }
            let kids = hits.map { h in
                CleanItem(id: "left:" + h.url.path, title: .raw(h.place), subtitle: .raw(h.url.lastPathComponent),
                          symbol: "ghost", tint: .purple, urls: [h.url], size: FS.size(of: h.url, cancel: cancel),
                          mode: .trash)
            }
            let total = kids.reduce(Int64(0)) { $0 + $1.size }
            guard total > 0 else { continue }
            let places = Array(Set(hits.map { $0.place })).sorted().joined(separator: ", ")
            let checked = total >= 1_000_000
            var kidsChecked = kids
            for i in kidsChecked.indices { kidsChecked[i].checkedByDefault = checked }
            if let p = CleanItem.parent(id: "leftover:" + id, title: .raw(prettyName(id)),
                                        subtitle: .key("sub.leftover", [id, places]),
                                        symbol: "ghost", tint: .purple, mode: .trash, children: kidsChecked) {
                items.append(p)
            }
        }
        return [CleanGroup(id: "leftovers", title: .key("group.leftovers"), items: items)]
    }

    /// "com.spotify.client" → "Spotify", "org.videolan.vlc" → "Vlc", "com.vendor.App-Helper" → "App Helper".
    static func prettyName(_ id: String) -> String {
        let labels = id.split(separator: ".").map(String.init)
        let generic: Set<String> = ["client", "app", "mac", "macos", "desktop", "osx", "helper", "agent", "launcher", "main"]
        var pick = labels.last ?? id
        if generic.contains(pick), labels.count >= 2 { pick = labels[labels.count - 2] }
        let words = pick.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
