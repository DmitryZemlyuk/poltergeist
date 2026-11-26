import SwiftUI
import AppKit
import PoltergeistKit

struct DiskMapView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmTrash: FSNode?

    var body: some View {
        Group {
            if let current = model.mapCurrent {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Breadcrumbs(node: current)
                        TreemapView(node: current, version: model.mapVersion)
                    }
                    .padding(16)
                    Divider()
                    Inspector(node: model.mapSelected ?? current, onTrash: { confirmTrash = $0 })
                        .frame(width: 300)
                }
            } else if model.mapScanning {
                ScanningView(text: LF("map.scanning", model.mapProgress))
            } else {
                ContentUnavailableView {
                    Label(L("map.empty.title"), systemImage: "chart.pie")
                } description: {
                    Text(L("map.empty.text"))
                } actions: {
                    Button(L("map.scan.home")) { model.scanMap(FS.home) }.prominentAction()
                    Button(L("map.choose")) { model.chooseMapFolder() }
                }
            }
        }
        .navigationTitle(L("section.map"))
        .navigationSubtitle(model.mapRoot.map { "\(FS.tilde($0.url)) · \(bytes($0.size))" } ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.chooseMapFolder() } label: { Label(L("map.choose"), systemImage: "folder") }
                    .help(L("map.choose"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.scanMap(nil) } label: { Label(L("action.rescan"), systemImage: "arrow.clockwise") }
                    .help(L("action.rescan"))
                    .disabled(model.mapScanning)
            }
        }
        .alert(L("trash.confirm.title"), isPresented: Binding(get: { confirmTrash != nil }, set: { if !$0 { confirmTrash = nil } }),
               presenting: confirmTrash) { node in
            Button(L("action.totrash"), role: .destructive) { model.trashNodes([node]) }
            Button(L("cancel"), role: .cancel) {}
        } message: { node in
            Text(LF("trash.confirm.text", node.name, bytes(node.size)))
        }
    }
}

struct Breadcrumbs: View {
    @EnvironmentObject var model: AppModel
    let node: FSNode

    var body: some View {
        HStack(spacing: 4) {
            Button { if let p = node.parent { model.mapCurrent = p; model.mapSelected = node } } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(node.parent == nil)
            .help(L("map.up"))
            ForEach(Array(node.chain.enumerated()), id: \.element.id) { i, n in
                if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                Button(i == 0 ? FS.tilde(n.url) : n.name) { model.mapCurrent = n; model.mapSelected = nil }
                    .buttonStyle(.plain)
                    .fontWeight(n === node ? .semibold : .regular)
                    .foregroundStyle(n === node ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

struct TreemapView: View {
    @EnvironmentObject var model: AppModel
    let node: FSNode
    let version: Int

    static let palette: [Color] = [.indigo, .teal, .orange, .blue, .pink, .green, .purple, .mint, .yellow, .red, .cyan, .brown]

    var body: some View {
        GeometryReader { geo in
            let shown = Array(node.children.filter { $0.size > 0 }.prefix(80))
            let rest = node.size - shown.reduce(0) { $0 + $1.size }
            let values = shown.map { Double($0.size) } + [Double(max(0, rest))]
            let rects = Treemap.layout(values, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, child in
                    let r = rects[i].insetBy(dx: 1.5, dy: 1.5)
                    if r.width > 2 && r.height > 2 {
                        Block(node: child, color: child.isAggregate ? .gray : Self.palette[i % Self.palette.count],
                              selected: model.mapSelected === child, size: r.size)
                            .frame(width: r.width, height: r.height)
                            .offset(x: r.minX, y: r.minY)
                            .onTapGesture(count: 2) { model.drill(child) }
                            .onTapGesture { model.mapSelected = child }
                    }
                }
            }
        }
        .id(version)
    }
}

struct Block: View {
    let node: FSNode
    let color: Color
    let selected: Bool
    let size: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: min(10, min(size.width, size.height) / 4), style: .continuous)
            .fill(color.opacity(node.isAggregate ? 0.12 : 0.22))
            .overlay {
                RoundedRectangle(cornerRadius: min(10, min(size.width, size.height) / 4), style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : color.opacity(0.35), lineWidth: selected ? 2 : 0.5)
            }
            .overlay(alignment: .topLeading) {
                if size.width > 64 && size.height > 34 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.isAggregate ? L("map.other") : node.name)
                            .font(.callout.weight(.semibold)).lineLimit(1)
                        Text(bytes(node.size)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
            .contentShape(Rectangle())
            .help("\(node.isAggregate ? L("map.other") : node.name) – \(bytes(node.size))")
    }
}

struct Inspector: View {
    @EnvironmentObject var model: AppModel
    let node: FSNode
    let onTrash: (FSNode) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    if node.isAggregate {
                        Image(systemName: "doc.on.doc").font(.largeTitle).foregroundStyle(.secondary).frame(width: 44, height: 44)
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
                            .resizable().frame(width: 44, height: 44)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.isAggregate ? L("map.other") : node.name).font(.title3.bold()).lineLimit(2)
                        Text(FS.tilde(node.isAggregate ? node.url.deletingLastPathComponent() : node.url))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                    }
                }
                HStack(spacing: 10) {
                    Stat(value: bytes(node.size), label: L("stat.size"))
                    Stat(value: node.fileCount.formatted(), label: L("stat.files"))
                    if let d = node.modified {
                        Stat(value: d.formatted(.relative(presentation: .named)), label: L("stat.modified"))
                    }
                }
                if node.isDirectory && !node.children.isEmpty {
                    Text(L("map.inside")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(Array(node.children.prefix(10))) { c in
                            Button { model.mapSelected = c } label: {
                                HStack {
                                    Text(c.isAggregate ? L("map.other") : c.name).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text(bytes(c.size)).foregroundStyle(.secondary).monospacedDigit()
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if c !== node.children.prefix(10).last { Divider().padding(.leading, 10) }
                        }
                    }
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                HStack {
                    if node.isDirectory && !node.children.isEmpty && node !== model.mapCurrent {
                        Button(L("map.open")) { model.drill(node) }
                    }
                    Button(L("action.reveal")) {
                        NSWorkspace.shared.activateFileViewerSelecting([node.isAggregate ? node.url.deletingLastPathComponent() : node.url])
                    }
                    Spacer()
                }
                if !node.isAggregate && node.parent != nil {
                    Button(role: .destructive) { onTrash(node) } label: {
                        Label(L("action.totrash"), systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .disabled(model.cleaning || !SafetyGuard().isAllowed(node.url, mode: .trash))
                }
            }
            .padding(16)
        }
    }
}

struct Stat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Large files

struct LargeFilesView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.largeFileMB) private var thresholdMB = 500
    @State private var picked: Set<ObjectIdentifier> = []
    @State private var confirm = false

    private var files: [FSNode] {
        _ = model.mapVersion
        return model.mapRoot?.files(atLeast: Int64(thresholdMB) * 1_000_000) ?? []
    }

    var body: some View {
        let list = files
        let chosen = list.filter { picked.contains($0.id) }
        let chosenSize = chosen.reduce(Int64(0)) { $0 + $1.size }
        Group {
            if model.mapRoot != nil {
                if list.isEmpty {
                    ContentUnavailableView(L("large.empty"), systemImage: "sparkles",
                                           description: Text(LF("large.empty.text", thresholdText)))
                } else {
                    Form {
                        Section {
                            ForEach(list) { f in
                                HStack(spacing: 10) {
                                    Toggle(f.name, isOn: Binding(get: { picked.contains(f.id) },
                                                                 set: { if $0 { picked.insert(f.id) } else { picked.remove(f.id) } }))
                                        .toggleStyle(.checkbox).labelsHidden()
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: f.url.path)).resizable().frame(width: 26, height: 26)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(f.name).lineLimit(1).truncationMode(.middle)
                                        Text(FS.tilde(f.url.deletingLastPathComponent()) + (f.modified.map { " · " + $0.formatted(date: .abbreviated, time: .omitted) } ?? ""))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer()
                                    Text(bytes(f.size)).foregroundStyle(.secondary).monospacedDigit()
                                }
                                .contextMenu {
                                    Button(L("action.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([f.url]) }
                                }
                            }
                        } header: {
                            Text(LF("large.header", list.count, thresholdText))
                        }
                    }
                    .formStyle(.grouped)
                }
            } else if model.mapScanning {
                ScanningView(text: LF("map.scanning", model.mapProgress))
            } else {
                ContentUnavailableView {
                    Label(L("large.need.title"), systemImage: "doc.badge.ellipsis")
                } description: {
                    Text(L("large.need.text"))
                } actions: {
                    Button(L("map.scan.home")) { model.scanMap(FS.home) }.prominentAction()
                }
            }
        }
        .navigationTitle(L("section.large"))
        .navigationSubtitle(model.mapRoot.map { FS.tilde($0.url) } ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker(L("large.threshold"), selection: $thresholdMB) {
                    Text("100 MB").tag(100)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1000)
                    Text("5 GB").tag(5000)
                }
                .pickerStyle(.menu)
                .help(L("large.threshold"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button(chosen.isEmpty ? L("action.totrash") : LF("action.totrash.size", bytes(chosenSize))) { confirm = true }
                    .prominentAction()
                    .disabled(chosen.isEmpty || model.cleaning)
            }
        }
        .alert(L("trash.confirm.title"), isPresented: $confirm) {
            Button(L("action.totrash"), role: .destructive) {
                model.trashNodes(chosen)
                picked.removeAll()
            }
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(LF("trash.confirm.many", chosen.count, bytes(chosenSize)))
        }
    }

    private var thresholdText: String {
        bytes(Int64(thresholdMB) * 1_000_000)
    }
}
