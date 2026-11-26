import Foundation
import CoreGraphics

/// A folder or file in the disk map. Small things are folded into one "other files" node per folder.
public final class FSNode: Identifiable, @unchecked Sendable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
    public let url: URL
    public let isDirectory: Bool
    /// The "other files" bucket of a folder.
    public let isAggregate: Bool
    public internal(set) var size: Int64
    public internal(set) var fileCount: Int
    public internal(set) var children: [FSNode]
    public internal(set) weak var parent: FSNode?
    public let modified: Date?

    init(url: URL, isDirectory: Bool, isAggregate: Bool = false, size: Int64 = 0, fileCount: Int = 0, modified: Date? = nil) {
        self.url = url
        self.isDirectory = isDirectory
        self.isAggregate = isAggregate
        self.size = size
        self.fileCount = fileCount
        self.children = []
        self.modified = modified
    }

    public var name: String { url.lastPathComponent }

    /// Path from the root down to this node.
    public var chain: [FSNode] {
        var out: [FSNode] = [self]
        var p = parent
        while let n = p { out.insert(n, at: 0); p = n.parent }
        return out
    }

    /// Files at least `minSize` big anywhere below.
    public func files(atLeast minSize: Int64) -> [FSNode] {
        var out: [FSNode] = []
        func walk(_ n: FSNode) {
            for c in n.children {
                if c.isAggregate { continue }
                if !c.isDirectory { if c.size >= minSize { out.append(c) } } else if c.size >= minSize { walk(c) }
            }
        }
        walk(self)
        return out.sorted { $0.size > $1.size }
    }

    /// Takes a node out of the tree after it was deleted, fixing the sizes above it.
    public func detach() {
        guard let p = parent else { return }
        p.children.removeAll { $0 === self }
        var a: FSNode? = p
        while let n = a {
            n.size -= size
            n.fileCount -= fileCount
            a = n.parent
        }
        parent = nil
    }
}

public final class DiskIndexer {
    public let minKeep: Int64
    /// Absolute paths that are not entered (e.g. other apps' containers without Full Disk Access).
    public let skip: Set<String>
    static let alwaysSkip: Set<String> = ["/System/Volumes", "/Volumes", "/dev", "/net", "/home", "/private/var/vm",
                                          "/System/Library/AssetsV2"]

    private var counted = 0
    private let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .totalFileAllocatedSizeKey,
                                          .fileAllocatedSizeKey, .contentModificationDateKey]

    public init(minKeep: Int64 = 1_000_000, skip: Set<String> = []) {
        self.minKeep = minKeep
        self.skip = skip.union(Self.alwaysSkip)
    }

    public func scan(_ root: URL, cancel: CancelFlag? = nil, progress: ((Int) -> Void)? = nil) -> FSNode {
        counted = 0
        let node = FSNode(url: root, isDirectory: true, modified: FS.modified(root))
        fill(node, collapse: false, cancel: cancel, progress: progress)
        progress?(counted)
        return node
    }

    private func fill(_ dir: FSNode, collapse: Bool, cancel: CancelFlag?, progress: ((Int) -> Void)?) {
        if cancel?.isCancelled == true { return }
        let kids = (try? FileManager.default.contentsOfDirectory(at: dir.url, includingPropertiesForKeys: keys, options: [])) ?? []
        var small: Int64 = 0
        var smallCount = 0
        var keep: [FSNode] = []
        for u in kids {
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isSymbolicLink == true { continue }
            if v.isDirectory == true {
                if skip.contains(u.path) { continue }
                let child = FSNode(url: u, isDirectory: true, modified: v.contentModificationDate)
                // Bundles (apps, photo libraries) and node_modules are shown as one block.
                let fold = collapse || v.isPackage == true || u.lastPathComponent == "node_modules"
                fill(child, collapse: fold, cancel: cancel, progress: progress)
                if collapse || child.size < minKeep {
                    small += child.size
                    smallCount += child.fileCount
                } else {
                    if fold { child.children = [] }
                    child.parent = dir
                    keep.append(child)
                }
            } else {
                let s = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                counted += 1
                if counted % 5000 == 0 { progress?(counted) }
                if collapse || s < minKeep {
                    small += s
                    smallCount += 1
                } else {
                    let f = FSNode(url: u, isDirectory: false, size: s, fileCount: 1, modified: v.contentModificationDate)
                    f.parent = dir
                    keep.append(f)
                }
            }
        }
        if !collapse && small > 0 {
            let agg = FSNode(url: dir.url.appendingPathComponent("…"), isDirectory: false, isAggregate: true,
                             size: small, fileCount: smallCount)
            agg.parent = dir
            keep.append(agg)
        }
        dir.children = keep.sorted { $0.size > $1.size }
        dir.size = keep.reduce(0) { $0 + $1.size } + (collapse ? small : 0)
        dir.fileCount = keep.reduce(0) { $0 + $1.fileCount } + (collapse ? smallCount : 0)
    }
}

/// Squarified treemap layout (Bruls, Huizing, van Wijk).
public enum Treemap {
    public static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: values.count)
        let order = values.indices.filter { values[$0] > 0 }.sorted { values[$0] > values[$1] }
        let total = order.reduce(0.0) { $0 + values[$1] }
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }
        let scale = Double(rect.width * rect.height) / total
        let areas = order.map { values[$0] * scale }

        func worst(_ row: ArraySlice<Double>, _ side: Double) -> Double {
            let sum = row.reduce(0, +)
            guard sum > 0, let mx = row.max(), let mn = row.min(), mn > 0 else { return .infinity }
            return max(side * side * mx / (sum * sum), sum * sum / (side * side * mn))
        }

        var r = rect
        var i = 0
        while i < areas.count {
            let side = Double(min(r.width, r.height))
            var j = i + 1
            while j < areas.count, worst(areas[i...j], side) <= worst(areas[i..<j], side) { j += 1 }
            let row = areas[i..<j]
            let sum = row.reduce(0, +)
            if r.width >= r.height {
                let w = CGFloat(sum / Double(r.height))
                var y = r.minY
                for (k, a) in row.enumerated() {
                    let h = CGFloat(a) / w
                    result[order[i + k]] = CGRect(x: r.minX, y: y, width: w, height: h)
                    y += h
                }
                r = CGRect(x: r.minX + w, y: r.minY, width: max(0, r.width - w), height: r.height)
            } else {
                let h = CGFloat(sum / Double(r.width))
                var x = r.minX
                for (k, a) in row.enumerated() {
                    let w = CGFloat(a) / h
                    result[order[i + k]] = CGRect(x: x, y: r.minY, width: w, height: h)
                    x += w
                }
                r = CGRect(x: r.minX, y: r.minY + h, width: r.width, height: max(0, r.height - h))
            }
            i = j
        }
        return result
    }
}
