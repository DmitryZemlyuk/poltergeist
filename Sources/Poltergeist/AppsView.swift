import SwiftUI
import AppKit
import PoltergeistKit

struct AppsView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var sort = Sort.size
    @State private var uninstalling: AppInfo?

    enum Sort: String, CaseIterable, Identifiable {
        case size, name, lastUsed
        var id: String { rawValue }
        var title: String { L("apps.sort." + rawValue) }
    }

    private var shown: [AppInfo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let list = model.apps.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
        switch sort {
        case .name: return list
        case .size: return list.sorted { (model.appSizes[$0.id] ?? -1) > (model.appSizes[$1.id] ?? -1) }
        case .lastUsed: return list.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
    }

    var body: some View {
        Group {
            if model.appsLoading && model.apps.isEmpty {
                ScanningView()
            } else {
                Form {
                    Section {
                        ForEach(shown) { app in AppRow(app: app) { uninstalling = app } }
                    } header: {
                        Text(LF("apps.header", model.apps.count))
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle(L("section.apps"))
        .navigationSubtitle(LF("apps.subtitle", bytes(model.appSizes.values.reduce(0, +))))
        .searchable(text: $query, placement: .toolbar, prompt: L("search.prompt"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker(L("apps.sort"), selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .help(L("apps.sort"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.loadApps() } label: { Label(L("action.rescan"), systemImage: "arrow.clockwise") }
                    .help(L("action.rescan"))
                    .disabled(model.appsLoading)
            }
        }
        .sheet(item: $uninstalling) { UninstallSheet(app: $0) }
    }
}

struct AppRow: View {
    @EnvironmentObject var model: AppModel
    let app: AppInfo
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text(lastUsedText).font(.caption).foregroundStyle(isStale ? Color.orange : Color.secondary)
            }
            Spacer()
            if let s = model.appSizes[app.id] {
                Text(bytes(s)).foregroundStyle(.secondary).monospacedDigit()
            } else {
                ProgressView().controlSize(.small)
            }
            Button(L("apps.uninstall"), action: onUninstall)
        }
        .contextMenu {
            Button(L("action.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
        }
    }

    private var isStale: Bool {
        guard let d = app.lastUsed else { return false }
        return Date().timeIntervalSince(d) > 180 * 86_400
    }

    private var lastUsedText: String {
        var parts: [String] = []
        if let v = app.version { parts.append(v) }
        if let d = app.lastUsed {
            parts.append(LF("apps.lastused", d.formatted(.relative(presentation: .named))))
        } else {
            parts.append(L("apps.lastused.unknown"))
        }
        return parts.joined(separator: " · ")
    }
}

struct UninstallSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let app: AppInfo
    @State private var related: [CleanItem]?
    @State private var picked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LF("uninstall.title", app.name)).font(.title2.bold())
                    Text(FS.tilde(app.url)).font(.caption).foregroundStyle(.secondary)
                }
            }
            if isRunning {
                Label(L("uninstall.running"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if let related {
                if related.isEmpty {
                    Text(L("uninstall.norelated")).foregroundStyle(.secondary)
                } else {
                    Text(L("uninstall.related")).font(.headline)
                    List(related) { item in
                        HStack {
                            Toggle(T(item.title), isOn: Binding(get: { picked.contains(item.id) },
                                                                set: { if $0 { picked.insert(item.id) } else { picked.remove(item.id) } }))
                                .toggleStyle(.checkbox).labelsHidden()
                            VStack(alignment: .leading, spacing: 1) {
                                Text(T(item.title))
                                if let s = item.subtitle { Text(T(s)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                            }
                            Spacer()
                            Text(bytes(item.size)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .frame(height: 200)
                }
                if !model.fullDiskAccess {
                    Text(L("uninstall.fda")).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text(L("uninstall.searching")).foregroundStyle(.secondary) }
            }
            HStack {
                Text(LF("uninstall.total", bytes(total))).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button(L("cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("uninstall.go"), role: .destructive) {
                    let items = (related ?? []).filter { picked.contains($0.id) }
                    model.uninstall(app, items: items)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(related == nil || model.cleaning)
            }
        }
        .padding(22)
        .frame(width: 520)
        .task {
            let r = await model.related(for: app)
            related = r
            picked = Set(r.map(\.id))
        }
    }

    private var isRunning: Bool {
        guard let id = app.bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    private var total: Int64 {
        (model.appSizes[app.id] ?? 0) + (related ?? []).filter { picked.contains($0.id) }.reduce(0) { $0 + $1.size }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(AppLanguage.key) private var language = ""
    @AppStorage(Prefs.oldDownloadsDays) private var downloadsDays = 90
    @AppStorage(Prefs.oldProjectsDays) private var projectsDays = 90

    var body: some View {
        Form {
            Section {
                Picker(L("settings.language"), selection: $language) {
                    Text(L("settings.language.system")).tag("")
                    Text("Українська").tag("uk")
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                }
                .onChange(of: language) { _, newValue in AppLanguage.apply(newValue) }
                if language != AppLanguage.atLaunch {
                    HStack {
                        Text(L("settings.language.restart")).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("settings.restart")) { AppLanguage.relaunch() }
                    }
                }
            }
            Section(L("settings.search")) {
                Picker(L("settings.downloads"), selection: $downloadsDays) { dayOptions }
                Picker(L("settings.projects"), selection: $projectsDays) { dayOptions }
            }
            Section(L("settings.access")) {
                Label(model.fullDiskAccess ? L("fda.on") : L("fda.off"),
                      systemImage: model.fullDiskAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.fullDiskAccess ? Color.green : Color.orange)
                Text(L("fda.explain")).font(.callout).foregroundStyle(.secondary)
                Button(L("fda.open")) { Access.openSettings() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var dayOptions: some View {
        ForEach([30, 60, 90, 180, 365], id: \.self) { d in
            Text(LF("settings.days", d)).tag(d)
        }
    }
}
