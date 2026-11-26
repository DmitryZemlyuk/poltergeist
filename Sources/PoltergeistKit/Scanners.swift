import Foundation

public enum ScanKind: String, CaseIterable, Sendable {
    case caches, developer, trash, backups, leftovers
}

public enum Scanners {
    public static func run(_ kind: ScanKind, _ c: ScanContext, cancel: CancelFlag? = nil) -> [CleanGroup] {
        let groups: [CleanGroup]
        switch kind {
        case .caches: groups = CachesScanner.scan(c, cancel: cancel)
        case .developer: groups = DeveloperScanner.scan(c, cancel: cancel)
        case .trash: groups = TrashScanner.scan(c, cancel: cancel)
        case .backups: groups = BackupsScanner.scan(c, cancel: cancel)
        case .leftovers: groups = LeftoversScanner.scan(c, cancel: cancel)
        }
        return groups.filter { !$0.items.isEmpty }
    }

    static func days(_ d: Date?, now: Date) -> Int? {
        guard let d else { return nil }
        return max(0, Int(now.timeIntervalSince(d) / 86_400))
    }
}

// MARK: - Caches and logs

public enum CachesScanner {
    /// Caches that belong to developer tools – shown under "Developer" instead.
    static let developerCaches: Set<String> = [
        "homebrew", "yarn", "cocoapods", "org.swift.swiftpm", "com.apple.dt.xcode", "com.apple.dt.xcodebuild",
        "pip", "node-gyp", "ms-playwright", "pnpm", "go-build", "typescript", "jetbrains", "google/androidstudio"
    ]

    /// Apple caches that are risky to drop (iCloud, keychain, maps state…). Never offered.
    static let appleKeep: Set<String> = [
        "com.apple.bird", "cloudkit", "com.apple.akd", "com.apple.nsurlsessiond", "com.apple.containermanagerd",
        "com.apple.ap.adprivacyd", "familycircle", "com.apple.homed", "com.apple.icloud.fmfd",
        "com.apple.amsengagementd", "com.apple.findmy.fmipcore", "com.crashlytics.data"
    ]

    public static func scan(_ c: ScanContext, cancel: CancelFlag?) -> [CleanGroup] {
        let names = InstalledApps.knownBundleIDs(folders: c.appFolders).names
        var cacheItems: [CleanItem] = []

        let caches = c.url("Library/Caches")
        let kids = FS.childItems(
            of: caches, idPrefix: "cache:", symbol: "cylinder.split.1x2", tint: .teal, mode: .remove,
            home: c.home, cancel: cancel,
            include: { u in
                let n = u.lastPathComponent.lowercased()
                return !developerCaches.contains(n) && !appleKeep.contains(n)
            },
            title: { u in .raw(names[u.lastPathComponent.lowercased()] ?? u.lastPathComponent) },
            subtitle: { u in names[u.lastPathComponent.lowercased()] != nil ? .raw(u.lastPathComponent) : nil },
            checked: { u in
                let n = u.lastPathComponent.lowercased()
                return !c.runningBundleIDs.contains(n) && !n.hasPrefix("com.apple.")
            },
            warning: { u in
                let n = u.lastPathComponent.lowercased()
                if c.runningBundleIDs.contains(n) { return .key("item.running") }
                if n.hasPrefix("com.apple.") { return .key("item.system") }
                return nil
            })
        if let p = CleanItem.parent(id: "caches.apps", title: .key("item.caches.apps"), symbol: "cylinder.split.1x2",
                                    tint: .teal, mode: .remove, children: kids) {
            cacheItems.append(p)
        }

        // Caches of App Store (sandboxed) apps live inside their containers. Reading those without
        // Full Disk Access makes macOS ask once per app, so they are only looked at with access.
        if c.fullDiskAccess {
            var boxed: [CleanItem] = []
            for box in FS.children(c.url("Library/Containers")) {
                if cancel?.isCancelled == true { break }
                let id = box.lastPathComponent.lowercased()
                if id.hasPrefix("com.apple.") { continue }
                let dir = box.appendingPathComponent("Data/Library/Caches")
                let s = FS.size(of: dir, cancel: cancel)
                guard s > 1_000_000 else { continue }
                let running = c.runningBundleIDs.contains(id)
                boxed.append(CleanItem(id: "boxcache:" + dir.path,
                                       title: .raw(names[id] ?? box.lastPathComponent),
                                       subtitle: names[id] != nil ? .raw(box.lastPathComponent) : nil,
                                       symbol: "app.dashed", tint: .blue,
                                       urls: FS.children(dir), size: s, mode: .remove,
                                       checkedByDefault: !running, warning: running ? .key("item.running") : nil))
            }
            if let p = CleanItem.parent(id: "caches.boxed", title: .key("item.caches.sandboxed"), symbol: "app.dashed",
                                        tint: .blue, mode: .remove, children: boxed) {
                cacheItems.append(p)
            }
        }

        var logItems: [CleanItem] = []
        let logs = c.url("Library/Logs")
        let logKids = FS.childItems(of: logs, idPrefix: "log:", symbol: "doc.text", tint: .gray, mode: .remove,
                                    home: c.home, cancel: cancel,
                                    include: { $0.lastPathComponent != "DiagnosticReports" })
        if let p = CleanItem.parent(id: "logs.apps", title: .key("item.logs.apps"), symbol: "doc.text",
                                    tint: .gray, mode: .remove, children: logKids) {
            logItems.append(p)
        }
        let reports = logs.appendingPathComponent("DiagnosticReports")
        let reportFiles = FS.children(reports)
        let reportSize = reportFiles.reduce(Int64(0)) { $0 + FS.size(of: $1) }
        if reportSize > 0 {
            logItems.append(CleanItem(id: "logs.crash", title: .key("item.logs.crash"),
                                      subtitle: .key("item.count", [String(reportFiles.count)]),
                                      symbol: "exclamationmark.triangle", tint: .orange,
                                      urls: reportFiles, size: reportSize, mode: .remove))
        }
        let saved = c.url("Library/Saved Application State")
        let savedKids = FS.children(saved)
        let savedSize = savedKids.reduce(Int64(0)) { $0 + FS.size(of: $1) }
        if savedSize > 0 {
            logItems.append(CleanItem(id: "logs.saved", title: .key("item.savedstate"), subtitle: .key("item.savedstate.sub"),
                                      symbol: "macwindow", tint: .indigo, urls: savedKids, size: savedSize,
                                      mode: .remove, checkedByDefault: false))
        }

        return [CleanGroup(id: "caches", title: .key("group.caches"), items: cacheItems),
                CleanGroup(id: "logs", title: .key("group.logs"), items: logItems)]
    }
}

// MARK: - Developer junk

public enum DeveloperScanner {
    public static func scan(_ c: ScanContext, cancel: CancelFlag?) -> [CleanGroup] {
        let h = c.home
        func folder(_ rel: String, _ key: String, _ symbol: String, _ tint: Tint, checked: Bool = true,
                    mode: DeleteMode = .remove) -> CleanItem? {
            FS.folderItem(c.url(rel), id: "dev:" + rel, title: .key(key), symbol: symbol, tint: tint,
                          mode: mode, checked: checked, home: h, cancel: cancel)
        }

        // Xcode
        var xcode: [CleanItem] = []
        let derived = c.url("Library/Developer/Xcode/DerivedData")
        let derivedKids = FS.childItems(of: derived, idPrefix: "dd:", symbol: "hammer", tint: .blue, mode: .remove,
                                        home: h, cancel: cancel,
                                        title: { u in
                                            // "MyApp-abcdefghijk" → "MyApp"
                                            let n = u.lastPathComponent
                                            if let dash = n.lastIndex(of: "-"), n.distance(from: dash, to: n.endIndex) > 20 {
                                                return .raw(String(n[..<dash]))
                                            }
                                            return .raw(n)
                                        })
        if let p = CleanItem.parent(id: "dev.derived", title: .raw("DerivedData"),
                                    subtitle: .raw("~/Library/Developer/Xcode/DerivedData"),
                                    symbol: "hammer", tint: .blue, mode: .remove, children: derivedKids) {
            xcode.append(p)
        }

        if Simulators.xcodeInstalled {
            let devices = Simulators.unavailable()
            let sims = devices.map { d -> CleanItem in
                let dir = c.url("Library/Developer/CoreSimulator/Devices/" + d.udid)
                return CleanItem(id: "sim:" + d.udid, title: .raw(d.name), subtitle: .raw(d.runtime),
                                 symbol: "iphone", tint: .blue, urls: [dir], size: FS.size(of: dir, cancel: cancel),
                                 mode: .simulator, payload: d.udid)
            }
            if let p = CleanItem.parent(id: "dev.sims", title: .key("item.simulators"), symbol: "iphone",
                                        tint: .blue, mode: .simulator, children: sims) {
                xcode.append(p)
            }
        }
        if let i = folder("Library/Developer/CoreSimulator/Caches", "item.simcaches", "iphone.gen2", .blue) { xcode.append(i) }

        var support: [CleanItem] = []
        for platform in ["iOS", "watchOS", "tvOS", "visionOS", "macOS"] {
            let dir = c.url("Library/Developer/Xcode/\(platform) DeviceSupport")
            let kids = FS.children(dir).filter { FS.isDirectory($0) }
            let newest = kids.max { (FS.modified($0) ?? .distantPast) < (FS.modified($1) ?? .distantPast) }
            for k in kids {
                let s = FS.size(of: k, cancel: cancel)
                guard s > 0 else { continue }
                let keep = k == newest
                support.append(CleanItem(id: "ds:" + k.path, title: .raw(k.lastPathComponent), subtitle: .raw(platform),
                                         symbol: "cpu", tint: .blue, urls: [k], size: s, mode: .remove,
                                         checkedByDefault: !keep, warning: keep ? .key("item.newest") : nil))
            }
        }
        if let p = CleanItem.parent(id: "dev.support", title: .raw("Device Support"), subtitle: .key("item.devicesupport.sub"),
                                    symbol: "cpu", tint: .blue, mode: .remove, children: support) {
            xcode.append(p)
        }

        var archives: [CleanItem] = []
        for day in FS.children(c.url("Library/Developer/Xcode/Archives")) where FS.isDirectory(day) {
            for a in FS.children(day) where a.pathExtension == "xcarchive" {
                let s = FS.size(of: a, cancel: cancel)
                guard s > 0 else { continue }
                archives.append(CleanItem(id: "arch:" + a.path, title: .raw(a.deletingPathExtension().lastPathComponent),
                                          subtitle: .raw(day.lastPathComponent), symbol: "archivebox", tint: .blue,
                                          urls: [a], size: s, mode: .trash, checkedByDefault: false))
            }
        }
        if let p = CleanItem.parent(id: "dev.archives", title: .raw("Archives"), subtitle: .key("item.archives.sub"),
                                    symbol: "archivebox", tint: .blue, mode: .trash, children: archives) {
            xcode.append(p)
        }
        if let i = folder("Library/Caches/com.apple.dt.Xcode", "item.xcodecache", "cylinder.split.1x2", .blue) { xcode.append(i) }
        if let i = folder("Library/Developer/Xcode/UserData/Previews", "item.previews", "eye", .blue) { xcode.append(i) }
        if let i = folder("Library/Caches/org.swift.swiftpm", "item.swiftpm", "swift", .orange) { xcode.append(i) }
        if let i = folder("Library/Caches/CocoaPods", "item.cocoapods", "shippingbox", .red) { xcode.append(i) }

        // Node and packages
        var node: [CleanItem] = []
        if let i = folder(".npm/_cacache", "item.npm", "shippingbox", .red) { node.append(i) }
        if let i = folder(".npm/_npx", "item.npx", "terminal", .red) { node.append(i) }
        if let i = folder("Library/Caches/Yarn", "item.yarn", "shippingbox", .blue) { node.append(i) }
        if let i = folder("Library/pnpm/store", "item.pnpm", "shippingbox", .orange, checked: false) { node.append(i) }
        if let i = folder("Library/Caches/node-gyp", "item.nodegyp", "gearshape.2", .green) { node.append(i) }
        if let i = folder(".nvm/.cache", "item.nvmcache", "arrow.down.circle", .green) { node.append(i) }
        node += nvmVersions(c, cancel: cancel)
        if let i = folder("Library/Caches/Homebrew", "item.brew", "mug", .orange) { node.append(i) }
        if let i = folder("Library/Caches/pip", "item.pip", "shippingbox", .yellow) { node.append(i) }
        if let i = folder("Library/Caches/ms-playwright", "item.playwright", "theatermasks", .green, checked: false) { node.append(i) }

        // Android and Java
        var android: [CleanItem] = []
        if let i = folder(".gradle/caches", "item.gradle", "cylinder.split.1x2", .green) { android.append(i) }
        if let i = folder(".gradle/daemon", "item.gradledaemon", "doc.text", .green) { android.append(i) }
        let dists = c.url(".gradle/wrapper/dists")
        let distKids = FS.children(dists).filter { FS.isDirectory($0) }
        let newestDist = distKids.max { (FS.modified($0) ?? .distantPast) < (FS.modified($1) ?? .distantPast) }
        let distItems = FS.childItems(of: dists, idPrefix: "gw:", symbol: "arrow.down.circle", tint: .green, mode: .remove,
                                      home: h, cancel: cancel,
                                      checked: { $0 != newestDist },
                                      warning: { $0 == newestDist ? .key("item.newest") : nil })
        if let p = CleanItem.parent(id: "dev.gradlewrapper", title: .key("item.gradlewrapper"), symbol: "arrow.down.circle",
                                    tint: .green, mode: .remove, children: distItems) {
            android.append(p)
        }
        if let i = folder(".android/cache", "item.androidcache", "cylinder.split.1x2", .green) { android.append(i) }
        let avds = FS.childItems(of: c.url(".android/avd"), idPrefix: "avd:", symbol: "iphone.gen3", tint: .green,
                                 mode: .trash, home: h, cancel: cancel,
                                 include: { $0.pathExtension == "avd" },
                                 title: { .raw($0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")) },
                                 checked: { _ in false })
        if let p = CleanItem.parent(id: "dev.avd", title: .key("item.avd"), symbol: "iphone.gen3", tint: .green,
                                    mode: .trash, children: avds) {
            android.append(p)
        }
        if let i = folder(".m2/repository", "item.maven", "shippingbox", .brown, checked: false) { android.append(i) }

        // Old projects
        var projects: [CleanItem] = []
        let modules = NodeModulesFinder.find(in: h, cancel: cancel)
        var mods: [CleanItem] = []
        for m in modules {
            let project = m.deletingLastPathComponent()
            let last = NodeModulesFinder.lastActivity(project)
            guard let d = Scanners.days(last, now: c.now), d >= c.oldProjectsDays else { continue }
            let s = FS.size(of: m, cancel: cancel)
            guard s > 0 else { continue }
            mods.append(CleanItem(id: "nm:" + m.path, title: .raw(project.lastPathComponent),
                                  subtitle: .key("sub.project", [FS.tilde(project, home: h), String(d)]),
                                  symbol: "folder", tint: .orange, urls: [m], size: s, mode: .remove,
                                  checkedByDefault: false))
        }
        if let p = CleanItem.parent(id: "dev.nodemodules", title: .key("item.nodemodules"),
                                    subtitle: .key("item.nodemodules.sub", [String(mods.count), String(c.oldProjectsDays)]),
                                    symbol: "folder", tint: .orange, mode: .remove, children: mods) {
            projects.append(p)
        }

        return [CleanGroup(id: "xcode", title: .raw("Xcode"), items: xcode),
                CleanGroup(id: "node", title: .key("group.node"), items: node),
                CleanGroup(id: "android", title: .key("group.android"), items: android),
                CleanGroup(id: "projects", title: .key("group.projects"), items: projects)]
    }

    /// Old Node versions installed with nvm. The newest one and the default one are never offered.
    static func nvmVersions(_ c: ScanContext, cancel: CancelFlag?) -> [CleanItem] {
        let dir = c.url(".nvm/versions/node")
        let versions = FS.children(dir).filter { $0.lastPathComponent.hasPrefix("v") && FS.isDirectory($0) }
        guard versions.count > 1 else { return [] }
        let parsed = versions.map { ($0, semver($0.lastPathComponent)) }
        let newest = parsed.max { $0.1.lexicographicallyPrecedes($1.1) }?.0
        var keep = Set<URL>()
        if let newest { keep.insert(newest) }
        if let alias = try? String(contentsOf: c.url(".nvm/alias/default"), encoding: .utf8) {
            let a = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            let want = a.hasPrefix("v") ? String(a.dropFirst()) : a
            if let first = want.first, first.isNumber {
                let matches = parsed.filter {
                    let v = String($0.0.lastPathComponent.dropFirst())
                    return v == want || v.hasPrefix(want + ".")
                }
                if let best = matches.max(by: { $0.1.lexicographicallyPrecedes($1.1) }) { keep.insert(best.0) }
            } else {
                // "node", "lts/*", "stable" and the like: can't tell which one – keep them all.
                return []
            }
        }
        let kids = versions.filter { !keep.contains($0) }.map { v in
            CleanItem(id: "nvm:" + v.path, title: .raw("Node " + v.lastPathComponent), subtitle: nil,
                      symbol: "chevron.left.forwardslash.chevron.right", tint: .green, urls: [v],
                      size: FS.size(of: v, cancel: cancel), mode: .remove)
        }
        let kept = keep.map { $0.lastPathComponent }.sorted().joined(separator: ", ")
        guard let p = CleanItem.parent(id: "dev.nvm", title: .key("item.nvm"), subtitle: .key("item.nvm.sub", [kept]),
                                       symbol: "chevron.left.forwardslash.chevron.right", tint: .green, mode: .remove,
                                       children: kids) else { return [] }
        return [p]
    }

    static func semver(_ s: String) -> [Int] {
        (s.hasPrefix("v") ? String(s.dropFirst()) : s).split(separator: ".").map { Int($0) ?? 0 }
    }
}

public enum NodeModulesFinder {
    static let skipTop: Set<String> = ["Library", "Applications", "Music", "Movies", "Pictures", "Public"]

    /// node_modules folders under home (not inside Library, hidden folders or other node_modules).
    public static func find(in home: URL, maxDepth: Int = 7, cancel: CancelFlag? = nil) -> [URL] {
        var result: [URL] = []
        func walk(_ dir: URL, _ depth: Int) {
            guard depth <= maxDepth, cancel?.isCancelled != true else { return }
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
            let kids = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [])) ?? []
            for u in kids {
                let name = u.lastPathComponent
                if name.hasPrefix(".") { continue }
                if depth == 0 && skipTop.contains(name) { continue }
                guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isDirectory == true,
                      v.isSymbolicLink != true, v.isPackage != true else { continue }
                if name == "node_modules" {
                    if FS.exists(dir.appendingPathComponent("package.json")) { result.append(u) }
                    continue
                }
                walk(u, depth + 1)
            }
        }
        walk(home, 0)
        return result
    }

    /// Latest change among the project's own files (node_modules itself doesn't count).
    public static func lastActivity(_ project: URL) -> Date? {
        var latest = FS.modified(project.appendingPathComponent("package.json"))
        for u in FS.children(project) where u.lastPathComponent != "node_modules" {
            if let d = FS.modified(u), d > (latest ?? .distantPast) { latest = d }
        }
        return latest
    }
}

// MARK: - Trash and Downloads

public enum TrashScanner {
    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip", "ipsw"]

    public static func scan(_ c: ScanContext, cancel: CancelFlag?) -> [CleanGroup] {
        var trashItems: [CleanItem] = []
        let trash = c.url(".Trash")
        if FS.canList(trash) {
            let kids = FS.children(trash)
            let size = kids.reduce(Int64(0)) { $0 + FS.size(of: $1, cancel: cancel) }
            if size > 0 {
                trashItems.append(CleanItem(id: "trash", title: .key("item.trash"),
                                            subtitle: .key("item.trash.sub", [String(kids.count)]),
                                            symbol: "trash", tint: .red, urls: [trash], size: size, mode: .emptyTrash))
            }
        } else if FS.exists(trash) {
            trashItems.append(CleanItem(id: "trash", title: .key("item.trash"), subtitle: .key("sub.needsaccess"),
                                        symbol: "trash", tint: .red, urls: [trash], size: 0, mode: .emptyTrash,
                                        checkedByDefault: false, needsAccess: true))
        }

        var dl: [CleanItem] = []
        let downloads = c.url("Downloads")
        var installers: [CleanItem] = []
        var old: [CleanItem] = []
        for u in FS.children(downloads) {
            if cancel?.isCancelled == true { break }
            let s = FS.size(of: u, cancel: cancel)
            guard s > 0 else { continue }
            let age = Scanners.days(FS.added(u), now: c.now) ?? 0
            let sub: Phrase = .key("sub.daysago", [String(age)])
            if installerExtensions.contains(u.pathExtension.lowercased()) {
                installers.append(CleanItem(id: "inst:" + u.path, title: .raw(u.lastPathComponent), subtitle: sub,
                                            symbol: "opticaldisc", tint: .green, urls: [u], size: s, mode: .trash))
            } else if age >= c.oldDownloadsDays {
                old.append(CleanItem(id: "old:" + u.path, title: .raw(u.lastPathComponent), subtitle: sub,
                                     symbol: "arrow.down.circle", tint: .green, urls: [u], size: s, mode: .trash,
                                     checkedByDefault: false))
            }
        }
        if let p = CleanItem.parent(id: "dl.installers", title: .key("item.installers"), symbol: "opticaldisc",
                                    tint: .green, mode: .trash, children: installers) {
            dl.append(p)
        }
        if let p = CleanItem.parent(id: "dl.old", title: .key("item.olddownloads", [String(c.oldDownloadsDays)]),
                                    symbol: "arrow.down.circle", tint: .green, mode: .trash, children: old) {
            dl.append(p)
        }
        return [CleanGroup(id: "trash", title: .key("group.trash"), items: trashItems),
                CleanGroup(id: "downloads", title: .key("group.downloads"), items: dl)]
    }
}

// MARK: - Device backups and Mail

public enum BackupsScanner {
    public static func scan(_ c: ScanContext, cancel: CancelFlag?) -> [CleanGroup] {
        var devices: [CleanItem] = []
        let backups = c.url("Library/Application Support/MobileSync/Backup")
        if FS.exists(backups) && !FS.canList(backups) {
            devices.append(CleanItem(id: "ios.backups", title: .key("item.iosbackups"), subtitle: .key("sub.needsaccess"),
                                     symbol: "iphone", tint: .orange, urls: [backups], size: 0, mode: .trash,
                                     checkedByDefault: false, needsAccess: true))
        } else {
            var kids: [CleanItem] = []
            for b in FS.children(backups) where FS.isDirectory(b) {
                let info = NSDictionary(contentsOf: b.appendingPathComponent("Info.plist")) as? [String: Any] ?? [:]
                let name = info["Device Name"] as? String ?? info["Display Name"] as? String ?? b.lastPathComponent
                let date = info["Last Backup Date"] as? Date ?? FS.modified(b)
                let s = FS.size(of: b, cancel: cancel)
                guard s > 0 else { continue }
                kids.append(CleanItem(id: "bk:" + b.path, title: .raw(name),
                                      subtitle: .key("sub.backupdate", [String(Scanners.days(date, now: c.now) ?? 0)]),
                                      symbol: "iphone", tint: .orange, urls: [b], size: s, mode: .trash,
                                      checkedByDefault: false))
            }
            if let p = CleanItem.parent(id: "ios.backups", title: .key("item.iosbackups"), symbol: "iphone",
                                        tint: .orange, mode: .trash, children: kids) {
                devices.append(p)
            }
        }
        var updates: [CleanItem] = []
        for folder in ["Library/iTunes/iPhone Software Updates", "Library/iTunes/iPad Software Updates",
                       "Library/iTunes/iPod Software Updates"] {
            updates += FS.childItems(of: c.url(folder), idPrefix: "ipsw:", symbol: "arrow.down.circle", tint: .orange,
                                     mode: .trash, home: c.home, cancel: cancel)
        }
        if let p = CleanItem.parent(id: "ios.ipsw", title: .key("item.ipsw"), symbol: "arrow.down.circle",
                                    tint: .orange, mode: .trash, children: updates) {
            devices.append(p)
        }

        var mail: [CleanItem] = []
        let mailDownloads = c.url("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
        if c.fullDiskAccess {
            let kids = FS.children(mailDownloads)
            let s = kids.reduce(Int64(0)) { $0 + FS.size(of: $1, cancel: cancel) }
            if s > 0 {
                mail.append(CleanItem(id: "mail.downloads", title: .key("item.maildownloads"),
                                      subtitle: .key("item.maildownloads.sub"), symbol: "envelope", tint: .blue,
                                      urls: kids, size: s, mode: .remove))
            }
        } else if FS.exists(c.url("Library/Containers/com.apple.mail")) {
            mail.append(CleanItem(id: "mail.downloads", title: .key("item.maildownloads"), subtitle: .key("sub.needsaccess"),
                                  symbol: "envelope", tint: .blue, urls: [mailDownloads], size: 0, mode: .remove,
                                  checkedByDefault: false, needsAccess: true))
        }
        return [CleanGroup(id: "devices", title: .key("group.devices"), items: devices),
                CleanGroup(id: "mail", title: .key("group.mail"), items: mail)]
    }
}
