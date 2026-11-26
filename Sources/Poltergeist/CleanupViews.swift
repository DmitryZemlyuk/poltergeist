import SwiftUI
import AppKit
import PoltergeistKit

// MARK: - Ghost

/// The app's ghost: a dome with a wavy hem. Drawn in a 16×20 box.
struct GhostShape: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(r.width / 16, r.height / 20)
        let ox = r.midX - 8 * s, oy = r.midY - 10 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + (x - 4) * s, y: oy + (y - 2) * s) }
        var path = Path()
        path.move(to: p(4, 22))
        path.addLine(to: p(4, 10))
        path.addCurve(to: p(12, 2), control1: p(4, 5.58), control2: p(7.58, 2))
        path.addCurve(to: p(20, 10), control1: p(16.42, 2), control2: p(20, 5.58))
        path.addLine(to: p(20, 22))
        path.addLine(to: p(17, 19))
        path.addLine(to: p(14.5, 21.5))
        path.addLine(to: p(12, 19))
        path.addLine(to: p(9.5, 21.5))
        path.addLine(to: p(7, 19))
        path.closeSubpath()
        return path
    }
}

/// Filled ghost with eye holes (inherits the foreground style).
struct GhostGlyph: View {
    var eyes = true
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width / 16, g.size.height / 20)
            ZStack {
                GhostShape()
                if eyes {
                    let ey = g.size.height / 2 - 10 * s + 8 * s
                    ForEach([5.0, 11.0], id: \.self) { x in
                        Capsule()
                            .frame(width: 2.4 * s, height: 3.2 * s)
                            .position(x: g.size.width / 2 - 8 * s + x * s, y: ey)
                            .blendMode(.destinationOut)
                    }
                }
            }
            .compositingGroup()
        }
    }
}

/// Coloured rounded tile with a white symbol, as in System Settings.
struct AppTile: View {
    let symbol: String
    let tint: Tint
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.color.gradient)
            .frame(width: size, height: size)
            .overlay {
                if symbol == "ghost" {
                    GhostGlyph().foregroundStyle(.white).frame(width: size * 0.5, height: size * 0.62)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.48, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityHidden(true)
    }
}

struct ScanningView: View {
    var text: String = L("scan.progress")
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AccessBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("fda.banner.title")).font(.headline)
                Text(L("fda.banner.text")).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("fda.open")) { Access.openSettings() }
        }
    }
}

// MARK: - A section with a list of junk

struct CleanupListView: View {
    @EnvironmentObject var model: AppModel
    let section: SectionID
    @State private var query = ""

    var body: some View {
        content
            .navigationTitle(section.title)
            .navigationSubtitle(subtitle)
            .searchable(text: $query, placement: .toolbar, prompt: L("search.prompt"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { model.scan(section) } label: {
                        Label(L("action.rescan"), systemImage: "arrow.clockwise")
                    }
                    .help(L("action.rescan"))
                    .disabled(model.scanning.contains(section))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(cleanTitle) { model.askToClean([section]) }
                        .prominentAction()
                        .disabled(model.selected(section) == 0 || model.cleaning || model.scanning.contains(section))
                }
            }
    }

    private var subtitle: String {
        if model.scanning.contains(section) && model.results[section] == nil { return L("scan.progress") }
        return LF("list.subtitle", bytes(model.found(section)), bytes(model.selected(section)))
    }

    private var cleanTitle: String {
        let s = model.selected(section)
        return s > 0 ? LF("action.clean.size", bytes(s)) : L("action.clean")
    }

    private var needsBanner: Bool {
        !model.fullDiskAccess && [.trash, .backups, .leftovers, .caches].contains(section)
    }

    @ViewBuilder private var content: some View {
        if let groups = model.results[section] {
            if groups.isEmpty {
                VStack(spacing: 18) {
                    ContentUnavailableView {
                        Label(L("empty.title"), systemImage: "sparkles")
                    } description: {
                        Text(L("empty.text"))
                    }
                    if needsBanner { AccessBanner().padding(.horizontal, 40).frame(maxWidth: 620) }
                }
            } else {
                Form {
                    if needsBanner { Section { AccessBanner() } }
                    ForEach(filtered(groups)) { g in
                        Section {
                            ForEach(g.items) { item in
                                ItemRow(item: item, section: section)
                            }
                        } header: {
                            HStack {
                                Text(T(g.title))
                                Spacer()
                                Text(bytes(g.size)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .overlay(alignment: .bottom) {
                    if model.scanning.contains(section) {
                        ProgressView().controlSize(.small).padding(10)
                    }
                }
            }
        } else {
            ScanningView()
        }
    }

    private func filtered(_ groups: [CleanGroup]) -> [CleanGroup] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return groups }
        func hit(_ i: CleanItem) -> Bool {
            T(i.title).localizedCaseInsensitiveContains(q)
                || (i.subtitle.map { T($0).localizedCaseInsensitiveContains(q) } ?? false)
                || i.urls.contains { $0.path.localizedCaseInsensitiveContains(q) }
        }
        return groups.compactMap { g in
            var g = g
            g.items = g.items.compactMap { item in
                if hit(item) { return item }
                var copy = item
                copy.children = item.children.filter(hit)
                return copy.children.isEmpty ? nil : copy
            }
            return g.items.isEmpty ? nil : g
        }
    }
}

struct ItemRow: View {
    @EnvironmentObject var model: AppModel
    let item: CleanItem
    let section: SectionID

    var body: some View {
        if item.children.isEmpty {
            RowContent(item: item, section: section, child: false)
        } else {
            DisclosureGroup(isExpanded: model.isExpanded(item.id)) {
                ForEach(item.children) { child in
                    RowContent(item: child, section: section, child: true)
                }
            } label: {
                RowContent(item: item, section: section, child: false)
            }
        }
    }
}

struct RowContent: View {
    @EnvironmentObject var model: AppModel
    let item: CleanItem
    let section: SectionID
    let child: Bool

    var body: some View {
        HStack(spacing: 10) {
            checkbox
            if !child { AppTile(symbol: item.symbol, tint: item.tint) }
            VStack(alignment: .leading, spacing: 1) {
                Text(T(item.title)).lineLimit(1).truncationMode(.middle)
                if let w = item.warning {
                    Text(T(w)).font(.caption).foregroundStyle(.orange)
                } else if let s = item.subtitle {
                    Text(T(s)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if item.needsAccess {
                Button(L("fda.open")) { Access.openSettings() }.controlSize(.small)
            } else {
                Text(bytes(item.size)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.vertical, child ? 0 : 2)
        .contentShape(Rectangle())
        .contextMenu {
            if !item.urls.isEmpty, item.mode != .simulator {
                Button(L("action.reveal")) { NSWorkspace.shared.activateFileViewerSelecting(Array(item.urls.prefix(20))) }
            }
        }
        .help(item.urls.count == 1 ? FS.tilde(item.urls[0]) : "")
    }

    @ViewBuilder private var checkbox: some View {
        let leaves = item.leaves.filter { !$0.needsAccess }
        if leaves.isEmpty {
            Toggle("", isOn: .constant(false)).toggleStyle(.checkbox).labelsHidden().disabled(true)
        } else if leaves.count == 1, let leaf = leaves.first {
            Toggle(T(item.title), isOn: Binding(get: { model.isSelected(leaf.id, in: section) },
                                                set: { model.setSelected(leaf.id, in: section, $0) }))
                .toggleStyle(.checkbox).labelsHidden()
        } else {
            // Native mixed state when only some children are picked.
            let sources = leaves.map { leaf in
                Binding(get: { model.isSelected(leaf.id, in: section) },
                        set: { model.setSelected(leaf.id, in: section, $0) })
            }
            Toggle(sources: sources, isOn: \.self) { Text(T(item.title)) }
                .toggleStyle(.checkbox).labelsHidden()
        }
    }
}

// MARK: - Overview

struct OverviewView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 28) {
                    DiskRing().frame(width: 150, height: 150)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LF("overview.found", bytes(model.totalFound))).font(.title2.bold())
                        Text(LF("overview.selected", bytes(model.totalSelected))).foregroundStyle(.secondary)
                        if let v = model.volume {
                            Text(LF("disk.free", bytes(v.available), bytes(v.total))).foregroundStyle(.secondary)
                        }
                        if !model.scanning.isEmpty {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(L("scan.progress")).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            if !model.fullDiskAccess { Section { AccessBanner() } }
            Section(L("overview.sections")) {
                ForEach(SectionID.lists) { s in
                    Button { model.section = s } label: {
                        HStack(spacing: 10) {
                            if s == .leftovers {
                                AppTile(symbol: "ghost", tint: s.tint)
                            } else {
                                AppTile(symbol: s.symbol, tint: s.tint)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.title)
                                Text(LF("overview.row.selected", bytes(model.selected(s))))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.scanning.contains(s) {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(bytes(model.found(s))).foregroundStyle(.secondary).monospacedDigit()
                            }
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L("section.overview"))
        .navigationSubtitle(model.volume?.name ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.scanAll() } label: { Label(L("action.scanall"), systemImage: "arrow.clockwise") }
                    .help(L("action.scanall"))
                    .disabled(!model.scanning.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(model.totalSelected > 0 ? LF("action.clean.size", bytes(model.totalSelected)) : L("action.clean")) {
                    model.askToClean(SectionID.lists)
                }
                .prominentAction()
                .disabled(model.totalSelected == 0 || model.cleaning || !model.scanning.isEmpty)
            }
        }
    }
}

/// Disk ring like the app icon: used space, junk in it, and free space.
struct DiskRing: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let total = Double(max(model.volume?.total ?? 1, 1))
        let used = Double(model.volume.map { $0.total - $0.available } ?? 0) / total
        let junk = min(used, Double(model.totalFound) / total)
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 14)
            Circle().trim(from: 0, to: max(0, used - junk))
                .stroke(Color.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 14))
                .rotationEffect(.degrees(-90))
            Circle().trim(from: max(0, used - junk), to: used)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 14))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(bytes(model.volume?.available ?? 0)).font(.title3.bold()).monospacedDigit()
                Text(L("ring.free")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
