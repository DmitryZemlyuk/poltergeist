import SwiftUI
import AppKit
import PoltergeistKit

enum SectionID: String, CaseIterable, Identifiable, Hashable {
    case overview, caches, developer, trash, backups, map, large, apps, leftovers

    var id: String { rawValue }
    var title: String { L("section." + rawValue) }

    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .caches: return "cylinder.split.1x2"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .trash: return "trash"
        case .backups: return "iphone"
        case .map: return "chart.pie"
        case .large: return "doc.badge.ellipsis"
        case .apps: return "square.grid.2x2"
        case .leftovers: return "ghost"
        }
    }

    var tint: Tint {
        switch self {
        case .overview: return .blue
        case .caches: return .teal
        case .developer: return .indigo
        case .trash: return .red
        case .backups: return .orange
        case .map: return .blue
        case .large: return .green
        case .apps: return .blue
        case .leftovers: return .purple
        }
    }

    var kind: ScanKind? {
        switch self {
        case .caches: return .caches
        case .developer: return .developer
        case .trash: return .trash
        case .backups: return .backups
        case .leftovers: return .leftovers
        default: return nil
        }
    }

    static let cleanup: [SectionID] = [.overview, .caches, .developer, .trash, .backups]
    static let analysis: [SectionID] = [.map, .large, .apps, .leftovers]
    /// Sections with a list of junk.
    static let lists: [SectionID] = [.caches, .developer, .trash, .backups, .leftovers]
}

/// What a clean-up is about to do, for the confirmation.
struct CleanPlan {
    var sections: [SectionID]
    var leaves: [CleanItem]
    var removeNow: Int64 { leaves.filter { $0.mode != .trash }.reduce(0) { $0 + $1.size } }
    var toTrash: Int64 { leaves.filter { $0.mode == .trash }.reduce(0) { $0 + $1.size } }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var section: SectionID = .overview
    @Published var results: [SectionID: [CleanGroup]] = [:]
    @Published var scanning: Set<SectionID> = []
    @Published var selection: [SectionID: Set<String>] = [:]
    @Published var expanded: Set<String> = []
    @Published var cleaning = false
    @Published var report: CleanReport?
    @Published var pendingPlan: CleanPlan?
    @Published var volume: VolumeInfo? = VolumeInfo.forHome()
    @Published var fullDiskAccess = FullDiskAccess.isGranted

    // Disk map
    @Published var mapRoot: FSNode?
    @Published var mapCurrent: FSNode?
    @Published var mapSelected: FSNode?
    @Published var mapScanning = false
    @Published var mapProgress = 0
    @Published var mapVersion = 0
    @Published var mapFolder: URL = FS.home

    // Apps
    @Published var apps: [AppInfo] = []
    @Published var appSizes: [String: Int64] = [:]
    @Published var appsLoading = false

    private var cancels: [SectionID: CancelFlag] = [:]
    private var mapCancel: CancelFlag?
    private var started = false

    // MARK: Start

    func start() {
        guard !started else { return }
        started = true
        scanAll()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshAccess() }
        }
    }

    func refreshAccess() {
        let now = FullDiskAccess.isGranted
        if now != fullDiskAccess {
            fullDiskAccess = now
            if now { scanAll() }
        }
        refreshVolume()
    }

    func refreshVolume() {
        volume = VolumeInfo.forHome()
    }

    func context() -> ScanContext {
        let d = UserDefaults.standard
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        return ScanContext(runningBundleIDs: running, fullDiskAccess: fullDiskAccess,
                           oldDownloadsDays: d.object(forKey: Prefs.oldDownloadsDays) as? Int ?? 90,
                           oldProjectsDays: d.object(forKey: Prefs.oldProjectsDays) as? Int ?? 90)
    }

    // MARK: Scanning

    func ensureScanned(_ s: SectionID) {
        switch s {
        case .apps: if apps.isEmpty && !appsLoading { loadApps() }
        default:
            if s.kind != nil, results[s] == nil, !scanning.contains(s) { scan(s) }
        }
    }

    func scanAll() {
        for s in SectionID.lists { scan(s) }
        refreshVolume()
    }

    func rescanCurrent() {
        switch section {
        case .overview: scanAll()
        case .map, .large: scanMap(mapFolder)
        case .apps: loadApps()
        default: scan(section)
        }
    }

    func scan(_ s: SectionID) {
        guard let kind = s.kind else { return }
        cancels[s]?.cancel()
        let flag = CancelFlag()
        cancels[s] = flag
        scanning.insert(s)
        let ctx = context()
        Task {
            let groups = await Task.detached(priority: .userInitiated) {
                Scanners.run(kind, ctx, cancel: flag)
            }.value
            guard !flag.isCancelled else { return }
            results[s] = groups
            let leaves = groups.flatMap { $0.items.flatMap(\.leaves) }
            selection[s] = Set(leaves.filter { $0.checkedByDefault && !$0.needsAccess }.map(\.id))
            scanning.remove(s)
        }
    }

    // MARK: Totals

    func leaves(_ s: SectionID) -> [CleanItem] {
        (results[s] ?? []).flatMap { $0.items.flatMap(\.leaves) }
    }

    func found(_ s: SectionID) -> Int64 {
        (results[s] ?? []).reduce(0) { $0 + $1.size }
    }

    func selectedLeaves(_ s: SectionID) -> [CleanItem] {
        let sel = selection[s] ?? []
        return leaves(s).filter { sel.contains($0.id) && !$0.needsAccess }
    }

    func selected(_ s: SectionID) -> Int64 {
        selectedLeaves(s).reduce(0) { $0 + $1.size }
    }

    /// Junk found everywhere. Leftovers overlap with caches, so each path counts once.
    var totalFound: Int64 { uniqueSize(SectionID.lists.flatMap { leaves($0) }) }
    var totalSelected: Int64 { uniqueSize(SectionID.lists.flatMap { selectedLeaves($0) }) }

    private func uniqueSize(_ items: [CleanItem]) -> Int64 {
        var seen = Set<String>()
        var total: Int64 = 0
        for i in items {
            let key = i.urls.map(\.path).joined(separator: "|") + (i.payload ?? "")
            if seen.insert(key).inserted { total += i.size }
        }
        return total
    }

    func badge(_ s: SectionID) -> String? {
        if s.kind != nil {
            if scanning.contains(s) && results[s] == nil { return "…" }
            let f = found(s)
            return f > 0 ? bytes(f) : nil
        }
        return nil
    }

    // MARK: Selection

    func isSelected(_ leafID: String, in s: SectionID) -> Bool {
        selection[s]?.contains(leafID) == true
    }

    func setSelected(_ leafID: String, in s: SectionID, _ on: Bool) {
        var sel = selection[s] ?? []
        if on { sel.insert(leafID) } else { sel.remove(leafID) }
        selection[s] = sel
    }

    func setAll(_ item: CleanItem, in s: SectionID, _ on: Bool) {
        var sel = selection[s] ?? []
        let ids = item.leaves.filter { !$0.needsAccess }.map(\.id)
        if on { sel.formUnion(ids) } else { sel.subtract(ids) }
        selection[s] = sel
    }

    func isExpanded(_ id: String) -> Binding<Bool> {
        Binding(get: { self.expanded.contains(id) },
                set: { if $0 { self.expanded.insert(id) } else { self.expanded.remove(id) } })
    }

    // MARK: Cleaning

    func askToClean(_ sections: [SectionID]) {
        // The same folder can sit in two sections (a cache of a removed app is also a leftover).
        var seen = Set<String>()
        let leaves = sections.flatMap { selectedLeaves($0) }.filter {
            seen.insert($0.urls.map(\.path).joined(separator: "|") + ($0.payload ?? "")).inserted
        }
        guard !leaves.isEmpty, !cleaning else { return }
        pendingPlan = CleanPlan(sections: sections, leaves: leaves)
    }

    func runPendingPlan() {
        guard let plan = pendingPlan else { return }
        pendingPlan = nil
        clean(plan.leaves, rescan: plan.sections)
    }

    func clean(_ leaves: [CleanItem], rescan: [SectionID], after: (@MainActor () -> Void)? = nil) {
        guard !leaves.isEmpty, !cleaning else { return }
        cleaning = true
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                Cleaner(trash: SystemTrash.recycle).clean(leaves)
            }.value
            cleaning = false
            self.report = report
            for s in rescan { scan(s) }
            after?()
            refreshVolume()
        }
    }

    // MARK: Disk map

    func scanMap(_ folder: URL?) {
        if let folder { mapFolder = folder }
        mapCancel?.cancel()
        let flag = CancelFlag()
        mapCancel = flag
        mapScanning = true
        mapProgress = 0
        mapRoot = nil
        mapCurrent = nil
        mapSelected = nil
        let root = mapFolder
        // Without Full Disk Access macOS would ask about every app's private folder.
        let skip: Set<String> = fullDiskAccess ? [] : [
            FS.home.appendingPathComponent("Library/Containers").path,
            FS.home.appendingPathComponent("Library/Group Containers").path
        ]
        Task {
            let node = await Task.detached(priority: .userInitiated) { [weak self] in
                DiskIndexer(skip: skip).scan(root, cancel: flag) { n in
                    Task { @MainActor in self?.mapProgress = n }
                }
            }.value
            guard !flag.isCancelled else { return }
            mapRoot = node
            mapCurrent = node
            mapScanning = false
            mapVersion += 1
        }
    }

    func chooseMapFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = mapFolder
        panel.prompt = L("map.choose.prompt")
        if panel.runModal() == .OK, let u = panel.url { scanMap(u) }
    }

    func drill(_ node: FSNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        mapCurrent = node
        mapSelected = nil
    }

    /// Moves files or folders from the map (or the large files list) to the Trash.
    func trashNodes(_ nodes: [FSNode]) {
        let items = nodes.filter { !$0.isAggregate && $0.parent != nil }.map {
            CleanItem(id: $0.url.path, title: .raw($0.name), symbol: "doc", tint: .gray, urls: [$0.url],
                      size: $0.size, mode: .trash)
        }
        guard !items.isEmpty else { return }
        clean(items, rescan: []) { [weak self] in
            guard let self else { return }
            let failed = Set((self.report?.failures ?? []).map(\.path))
            for n in nodes where !failed.contains(n.url.path) && !FS.exists(n.url) {
                if let cur = self.mapCurrent, cur.chain.contains(where: { $0 === n }) { self.mapCurrent = n.parent }
                if self.mapSelected === n { self.mapSelected = n.parent }
                n.detach()
            }
            self.mapVersion += 1
        }
    }

    // MARK: Apps

    func loadApps() {
        appsLoading = true
        Task {
            let list = await Task.detached(priority: .userInitiated) { InstalledApps.list() }.value
            apps = list
            appsLoading = false
            for app in list where appSizes[app.id] == nil {
                let s = await Task.detached(priority: .utility) { FS.size(of: app.url) }.value
                appSizes[app.id] = s
            }
        }
    }

    func related(for app: AppInfo) async -> [CleanItem] {
        let ctx = context()
        return await Task.detached(priority: .userInitiated) { AppFiles.related(to: app, ctx) }.value
    }

    func uninstall(_ app: AppInfo, items: [CleanItem]) {
        if let id = app.bundleID {
            for r in NSRunningApplication.runningApplications(withBundleIdentifier: id) { r.terminate() }
        }
        let appItem = CleanItem(id: app.id, title: .raw(app.name), symbol: "app", tint: .blue, urls: [app.url],
                                size: appSizes[app.id] ?? 0, mode: .trash)
        Task {
            // Give the app a moment to quit before its files move.
            try? await Task.sleep(nanoseconds: 800_000_000)
            clean([appItem] + items, rescan: [.leftovers]) { [weak self] in
                guard let self else { return }
                if !FS.exists(app.url) {
                    self.apps.removeAll { $0.id == app.id }
                    self.appSizes[app.id] = nil
                }
            }
        }
    }
}
