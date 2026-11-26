import XCTest
import CoreGraphics
@testable import PoltergeistKit

/// A throwaway home folder.
final class FakeHome {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("pg-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func file(_ rel: String, bytes: Int = 10_000, date: Date? = nil) throws -> URL {
        let u = url.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: u)
        if let date {
            try FileManager.default.setAttributes([.modificationDate: date, .creationDate: date], ofItemAtPath: u.path)
        }
        return u
    }

    func dir(_ rel: String) throws -> URL {
        let u = url.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func context(days: Int = 90) -> ScanContext {
        ScanContext(home: url, fullDiskAccess: true, oldDownloadsDays: days, oldProjectsDays: days, appFolders: [])
    }
}

final class TreemapTests: XCTestCase {
    func testAreasFillTheRect() {
        let values: [Double] = [50, 20, 10, 10, 5, 5, 0]
        let rect = CGRect(x: 0, y: 0, width: 600, height: 400)
        let rects = Treemap.layout(values, in: rect)
        XCTAssertEqual(rects.count, values.count)
        XCTAssertEqual(rects[6], .zero)
        let area = rects.reduce(0.0) { $0 + Double($1.width * $1.height) }
        XCTAssertEqual(area, 600 * 400, accuracy: 1)
        for (i, r) in rects.enumerated() where values[i] > 0 {
            XCTAssertGreaterThanOrEqual(r.minX, -0.01)
            XCTAssertGreaterThanOrEqual(r.minY, -0.01)
            XCTAssertLessThanOrEqual(r.maxX, 600.01)
            XCTAssertLessThanOrEqual(r.maxY, 400.01)
            XCTAssertEqual(Double(r.width * r.height), values[i] / 100 * 240_000, accuracy: 1)
        }
    }

    func testEmpty() {
        XCTAssertEqual(Treemap.layout([], in: CGRect(x: 0, y: 0, width: 10, height: 10)), [])
        XCTAssertEqual(Treemap.layout([0, 0], in: CGRect(x: 0, y: 0, width: 10, height: 10)), [.zero, .zero])
    }
}

final class SafetyTests: XCTestCase {
    func testGuard() throws {
        let h = try FakeHome()
        let g = SafetyGuard(home: h.url)
        XCTAssertFalse(g.isAllowed(h.url, mode: .remove))
        XCTAssertFalse(g.isAllowed(h.url.appendingPathComponent("Library"), mode: .remove))
        XCTAssertFalse(g.isAllowed(h.url.appendingPathComponent("Library/Caches"), mode: .remove))
        XCTAssertFalse(g.isAllowed(h.url.appendingPathComponent("Documents"), mode: .trash))
        XCTAssertFalse(g.isAllowed(h.url.appendingPathComponent("Library/Keychains/login.keychain-db"), mode: .remove))
        XCTAssertFalse(g.isAllowed(h.url.appendingPathComponent("Library/Mobile Documents/x"), mode: .trash))
        XCTAssertTrue(g.isAllowed(h.url.appendingPathComponent("Library/Caches/com.foo"), mode: .remove))
        XCTAssertTrue(g.isAllowed(h.url.appendingPathComponent(".npm/_cacache"), mode: .remove))
        XCTAssertFalse(g.isAllowed(h.url.appendingPathComponent("Library/Caches/../Caches"), mode: .remove))
        XCTAssertFalse(g.isAllowed(URL(fileURLWithPath: "/usr/local/bin"), mode: .remove))
        XCTAssertTrue(g.isAllowed(URL(fileURLWithPath: "/Applications/Foo.app"), mode: .trash))
        XCTAssertFalse(g.isAllowed(URL(fileURLWithPath: "/Applications/Foo.app"), mode: .remove))
        XCTAssertFalse(g.isAllowed(URL(fileURLWithPath: "/Applications"), mode: .trash))
    }
}

final class CleanerTests: XCTestCase {
    func testRemoveTrashAndProtect() throws {
        let h = try FakeHome()
        let cache = try h.file("Library/Caches/com.foo/a.bin")
        let dl = try h.file("Downloads/setup.dmg")
        var trashed: [URL] = []
        let cleaner = Cleaner(guardrail: SafetyGuard(home: h.url), trash: { trashed.append($0) }, simctl: { _ in })
        let items = [
            CleanItem(id: "1", title: .raw("c"), symbol: "x", tint: .teal, urls: [cache.deletingLastPathComponent()],
                      size: 10, mode: .remove),
            CleanItem(id: "2", title: .raw("d"), symbol: "x", tint: .green, urls: [dl], size: 20, mode: .trash),
            CleanItem(id: "3", title: .raw("p"), symbol: "x", tint: .gray, urls: [h.url.appendingPathComponent("Library/Caches")],
                      size: 30, mode: .remove),
            // Same folder again: handled once.
            CleanItem(id: "4", title: .raw("c2"), symbol: "x", tint: .teal, urls: [cache.deletingLastPathComponent()],
                      size: 10, mode: .remove)
        ]
        let r = cleaner.clean(items)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: h.url.appendingPathComponent("Library/Caches").path))
        XCTAssertEqual(trashed, [dl])
        XCTAssertEqual(r.freed, 10)
        XCTAssertEqual(r.trashed, 20)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r.failures.count, 1)
        XCTAssertEqual(r.failures.first?.reason, Cleaner.protected)
    }

    func testEmptyTrash() throws {
        let h = try FakeHome()
        try h.file(".Trash/old.txt")
        try h.file(".Trash/folder/x.txt")
        let item = CleanItem(id: "t", title: .raw("t"), symbol: "trash", tint: .red,
                             urls: [h.url.appendingPathComponent(".Trash")], size: 1, mode: .emptyTrash)
        let r = Cleaner(guardrail: SafetyGuard(home: h.url)).clean([item])
        XCTAssertEqual(r.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: h.url.appendingPathComponent(".Trash").path))
        XCTAssertEqual(FS.children(h.url.appendingPathComponent(".Trash")).count, 0)
    }
}

final class LeftoverTests: XCTestCase {
    func testBundleIDFromName() {
        XCTAssertEqual(LeftoversScanner.bundleID(fromName: "com.spotify.client.plist"), "com.spotify.client")
        XCTAssertEqual(LeftoversScanner.bundleID(fromName: "UBF8T346G9.com.microsoft.teams"), "com.microsoft.teams")
        XCTAssertEqual(LeftoversScanner.bundleID(fromName: "group.com.vendor.shared"), "com.vendor.shared")
        XCTAssertEqual(LeftoversScanner.bundleID(fromName: "org.videolan.vlc.savedState"), "org.videolan.vlc")
        XCTAssertNil(LeftoversScanner.bundleID(fromName: "Google"))
        XCTAssertNil(LeftoversScanner.bundleID(fromName: "com.vendor"))
        XCTAssertNil(LeftoversScanner.bundleID(fromName: "loginwindow.plist"))
        XCTAssertNil(LeftoversScanner.bundleID(fromName: "My Folder.with.dots"))
    }

    func testOwnership() {
        let installed: Set<String> = ["com.vendor.app"]
        let vendors: Set<String> = ["com.vendor"]
        XCTAssertTrue(LeftoversScanner.isOwned("com.vendor.app", installed: installed, vendors: vendors))
        XCTAssertTrue(LeftoversScanner.isOwned("com.vendor.app.helper", installed: installed, vendors: vendors))
        XCTAssertTrue(LeftoversScanner.isOwned("com.vendor.other", installed: installed, vendors: vendors))
        XCTAssertFalse(LeftoversScanner.isOwned("com.gone.app", installed: installed, vendors: vendors))
        XCTAssertTrue(LeftoversScanner.isSystem("com.apple.Safari".lowercased()))
        XCTAssertEqual(LeftoversScanner.prettyName("com.spotify.client"), "Spotify")
    }

    func testScanFindsLeftovers() throws {
        let h = try FakeHome()
        try h.file("Library/Application Support/com.gone.editor/data.db", bytes: 2_000_000)
        try h.file("Library/Preferences/com.gone.editor.plist", bytes: 2_000)
        try h.file("Library/Preferences/com.apple.finder.plist", bytes: 2_000)
        let groups = LeftoversScanner.scan(h.context(), cancel: nil)
        let items = groups.flatMap(\.items)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.children.count, 2)
        XCTAssertTrue(items.first?.checkedByDefault == true)
    }
}

final class ScannerTests: XCTestCase {
    func testDeveloperAndDownloads() throws {
        let h = try FakeHome()
        try h.file(".npm/_cacache/index/x", bytes: 50_000)
        try h.file("Library/Developer/Xcode/DerivedData/App-abcdefghijklmnopqrstuvwxyz/Build/x", bytes: 50_000)
        let old = Date(timeIntervalSinceNow: -200 * 86_400)
        try h.file("Projects/web/package.json", bytes: 100, date: old)
        try h.file("Projects/web/node_modules/left-pad/index.js", bytes: 50_000)
        try h.file("Projects/fresh/package.json", bytes: 100)
        try h.file("Projects/fresh/node_modules/x/index.js", bytes: 50_000)
        let dev = DeveloperScanner.scan(h.context(), cancel: nil)
        let ids = dev.flatMap(\.items).map(\.id)
        XCTAssertTrue(ids.contains { $0.contains("_cacache") }, "\(ids)")
        XCTAssertTrue(ids.contains { $0.contains("dev.derived") }, "\(ids)")
        let nm = dev.flatMap(\.items).first { $0.id.contains("dev.nodemodules") }
        XCTAssertNotNil(nm)
        XCTAssertEqual(nm?.leaves.count, 1)
        XCTAssertTrue(nm?.leaves.first?.urls.first?.path.contains("web/node_modules") == true)

        try h.file("Downloads/setup.dmg", bytes: 20_000)
        try h.file("Downloads/new.zip", bytes: 20_000)
        let t = TrashScanner.scan(h.context(), cancel: nil)
        let leaves = t.flatMap(\.items).flatMap(\.leaves).map { $0.urls.first?.lastPathComponent ?? "" }
        XCTAssertTrue(leaves.contains("setup.dmg"))
        XCTAssertFalse(leaves.contains("new.zip"))
    }

    func testCachesSkipDeveloperOnes() throws {
        let h = try FakeHome()
        try h.file("Library/Caches/com.foo.bar/x", bytes: 20_000)
        try h.file("Library/Caches/Homebrew/x", bytes: 20_000)
        let g = CachesScanner.scan(h.context(), cancel: nil)
        let paths = g.flatMap(\.items).flatMap(\.leaves).flatMap(\.urls).map(\.lastPathComponent)
        XCTAssertTrue(paths.contains("com.foo.bar"))
        XCTAssertFalse(paths.contains("Homebrew"))
    }

    func testRunningAppCacheIsLeftAlone() throws {
        let h = try FakeHome()
        try h.file("Library/Caches/Google/Chrome/x", bytes: 20_000)
        try h.file("Library/Caches/com.foo.bar/x", bytes: 20_000)
        var ctx = h.context()
        ctx.runningBundleIDs = ["com.google.chrome"]
        XCTAssertTrue(ctx.isRunning(folderNamed: "Google"))
        XCTAssertFalse(ctx.isRunning(folderNamed: "com.foo.bar"))
        let leaves = CachesScanner.scan(ctx, cancel: nil).flatMap(\.items).flatMap(\.leaves)
        XCTAssertEqual(leaves.first { $0.urls[0].lastPathComponent == "Google" }?.checkedByDefault, false)
        XCTAssertEqual(leaves.first { $0.urls[0].lastPathComponent == "com.foo.bar" }?.checkedByDefault, true)
    }

    func testNvmKeepsNewestAndDefault() throws {
        let h = try FakeHome()
        for v in ["v16.20.2", "v18.19.0", "v22.11.0"] { try h.file(".nvm/versions/node/\(v)/bin/node", bytes: 20_000) }
        try "18".write(to: h.url.appendingPathComponent(".nvm/alias/default").creatingParent(), atomically: true, encoding: .utf8)
        let items = DeveloperScanner.nvmVersions(h.context(), cancel: nil)
        let names = items.flatMap(\.leaves).flatMap(\.urls).map(\.lastPathComponent)
        XCTAssertEqual(names, ["v16.20.2"])
    }
}

final class DiskIndexTests: XCTestCase {
    func testTreeSizesAndDetach() throws {
        let h = try FakeHome()
        try h.file("big/a.bin", bytes: 3_000_000)
        try h.file("big/b.bin", bytes: 2_000_000)
        try h.file("small/c.txt", bytes: 1_000)
        try h.file("d.bin", bytes: 1_500_000)
        let root = DiskIndexer().scan(h.url)
        XCTAssertGreaterThan(root.size, 6_000_000)
        let big = root.children.first { $0.name == "big" }
        XCTAssertNotNil(big)
        XCTAssertEqual(big?.children.count, 2)
        XCTAssertTrue(root.children.contains { $0.isAggregate })
        XCTAssertEqual(root.files(atLeast: 1_400_000).count, 3)
        let before = root.size
        let a = big!.children.first { $0.name == "a.bin" }!
        a.detach()
        XCTAssertEqual(root.size, before - a.size)
        XCTAssertEqual(big?.children.count, 1)
    }
}

final class SimulatorTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(Simulators.runtimeName("com.apple.CoreSimulator.SimRuntime.iOS-17-5"), "iOS 17.5")
        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-16-4":[
          {"udid":"11111111-2222-3333-4444-555555555555","name":"iPhone 14","isAvailable":false},
          {"udid":"AAAAAAAA-2222-3333-4444-555555555555","name":"iPhone 15","isAvailable":true}]}}
        """.data(using: .utf8)!
        let d = Simulators.parseUnavailable(json)
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(d.first?.name, "iPhone 14")
        XCTAssertEqual(d.first?.runtime, "iOS 16.4")
    }
}

final class ModelTests: XCTestCase {
    func testParentFoldsSingleChild() {
        let child = CleanItem(id: "c", title: .raw("x"), symbol: "s", tint: .blue, urls: [URL(fileURLWithPath: "/tmp/x")],
                              size: 5, mode: .remove)
        let p = CleanItem.parent(id: "p", title: .key("k"), symbol: "t", tint: .red, mode: .remove, children: [child])
        XCTAssertEqual(p?.children.count, 0)
        XCTAssertEqual(p?.size, 5)
        XCTAssertNil(CleanItem.parent(id: "p", title: .key("k"), symbol: "t", tint: .red, mode: .remove, children: []))
        let two = CleanItem.parent(id: "p", title: .key("k"), symbol: "t", tint: .red, mode: .remove, children: [child, child])
        XCTAssertEqual(two?.leaves.count, 2)
        XCTAssertEqual(two?.size, 10)
    }
}

extension URL {
    func creatingParent() throws -> URL {
        try FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
}
