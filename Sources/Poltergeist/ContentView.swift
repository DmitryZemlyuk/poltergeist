import SwiftUI
import AppKit
import PoltergeistKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 300)
        } detail: {
            DetailView(section: model.section)
                .id(model.section)
        }
        .onAppear { model.start() }
        .sheet(item: $model.report) { ReportSheet(report: $0) }
        .alert(L("confirm.title"), isPresented: Binding(get: { model.pendingPlan != nil },
                                                         set: { if !$0 { model.pendingPlan = nil } }),
               presenting: model.pendingPlan) { _ in
            Button(L("confirm.go"), role: .destructive) { model.runPendingPlan() }
            Button(L("cancel"), role: .cancel) { model.pendingPlan = nil }
        } message: { plan in
            Text(confirmText(plan))
        }
    }

    private func confirmText(_ plan: CleanPlan) -> String {
        var lines: [String] = [LF("confirm.count", plan.leaves.count)]
        if plan.removeNow > 0 { lines.append(LF("confirm.now", bytes(plan.removeNow))) }
        if plan.toTrash > 0 { lines.append(LF("confirm.trash", bytes(plan.toTrash))) }
        return lines.joined(separator: "\n")
    }
}

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List(selection: Binding<SectionID?>(get: { model.section }, set: { if let v = $0 { model.section = v } })) {
            Section(L("sidebar.cleanup")) {
                ForEach(SectionID.cleanup) { row($0) }
            }
            Section(L("sidebar.analysis")) {
                ForEach(SectionID.analysis) { row($0) }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            DiskCard().padding(.horizontal, 12).padding(.bottom, 12)
        }
    }

    @ViewBuilder private func row(_ s: SectionID) -> some View {
        Label {
            Text(s.title)
        } icon: {
            SectionIcon(section: s)
        }
        .badge(model.badge(s).map { Text($0).monospacedDigit() })
        .tag(s)
    }
}

struct SectionIcon: View {
    let section: SectionID
    var body: some View {
        if section == .leftovers {
            // A template image, like an SF Symbol: tinted by the sidebar and white when the row is selected.
            Image(nsImage: GhostImage.template)
        } else {
            Image(systemName: section.symbol)
        }
    }
}

struct DiskCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let v = model.volume, v.total > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text(v.name).font(.callout.weight(.semibold))
                UsageBar(total: v.total, used: v.total - v.available, junk: model.totalFound)
                    .frame(height: 6)
                Text(LF("disk.free", bytes(v.available), bytes(v.total)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

struct UsageBar: View {
    let total: Int64
    let used: Int64
    let junk: Int64

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let usedF = CGFloat(Double(min(used, total)) / Double(max(total, 1)))
            let junkF = min(usedF, CGFloat(Double(junk) / Double(max(total, 1))))
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                HStack(spacing: 0) {
                    Rectangle().fill(Color.secondary.opacity(0.55)).frame(width: w * (usedF - junkF))
                    Rectangle().fill(Color.orange).frame(width: w * junkF)
                }
                .clipShape(Capsule())
            }
        }
    }
}

struct DetailView: View {
    @EnvironmentObject var model: AppModel
    let section: SectionID

    var body: some View {
        Group {
            switch section {
            case .overview: OverviewView()
            case .map: DiskMapView()
            case .large: LargeFilesView()
            case .apps: AppsView()
            default: CleanupListView(section: section)
            }
        }
        .task { model.ensureScanned(section) }
    }
}

struct ReportSheet: View {
    let report: CleanReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AppTile(symbol: "ghost", tint: .purple, size: 40)
                Text(report.failures.isEmpty ? L("report.title") : L("report.title.partial"))
                    .font(.title2.bold())
            }
            if report.freed > 0 { Label(LF("report.freed", bytes(report.freed)), systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            if report.trashed > 0 { Label(LF("report.trashed", bytes(report.trashed)), systemImage: "trash") }
            if report.freed == 0 && report.trashed == 0 && report.failures.isEmpty { Text(L("report.nothing")).foregroundStyle(.secondary) }
            if !report.failures.isEmpty {
                Text(LF("report.failed", report.failures.count)).font(.headline)
                List(report.failures) { f in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(FS.tilde(URL(fileURLWithPath: f.path))).font(.callout).lineLimit(1).truncationMode(.middle)
                        Text(reason(f.reason)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 160)
                if report.failures.contains(where: { $0.reason == Cleaner.noAccess }) {
                    Button(L("fda.open")) { Access.openSettings() }
                }
            }
            HStack {
                Spacer()
                Button(L("done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 470)
    }
}
