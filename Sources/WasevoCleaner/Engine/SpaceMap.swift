import Foundation
import CoreGraphics

// Wasevo Cleaner — Space Map: where the disk space actually goes. View only, never deletes.

struct MapNode: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let size: Int64
    let isDir: Bool
    var isVirtual = false          // e.g. "macOS, apps & system" (outside your home folder)
    var protected: String? { isVirtual ? nil : protectedReason(path + (isDir ? "/" : "")) }
}

/// Real allocated size of a folder via `du` (fast, counts sparse files correctly, stays on this disk).
func duSize(_ path: String) -> Int64 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
    p.arguments = ["-skx", path]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return 0 }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let first = String(decoding: data, as: UTF8.self).split(separator: "\t").first ?? "0"
    return (Int64(first.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) * 1024
}

/// Sizes of everything directly inside `dir`, biggest first. Folders are measured in parallel.
func mapChildren(of dir: String, progress: @escaping (Int, Int) -> Void) -> [MapNode] {
    let fm = FileManager.default
    let kids = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0 != ".DS_Store" }
    var nodes = [MapNode?](repeating: nil, count: kids.count)
    let lock = NSLock()
    var done = 0
    DispatchQueue.concurrentPerform(iterations: kids.count) { i in
        let p = (dir as NSString).appendingPathComponent(kids[i])
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: p, isDirectory: &isDir)
        let link = (try? fm.destinationOfSymbolicLink(atPath: p)) != nil
        var node: MapNode?
        if exists && !link {
            let size = isDir.boolValue ? duSize(p) : dirSize(p)
            if size > 0 { node = MapNode(name: kids[i], path: p, size: size, isDir: isDir.boolValue) }
        }
        lock.lock(); nodes[i] = node; done += 1; let d = done; lock.unlock()
        progress(d, kids.count)
    }
    return nodes.compactMap { $0 }.sorted { $0.size > $1.size }
}

// MARK: squarified treemap layout

struct MapTile: Identifiable {
    var id: String { node.id }
    let node: MapNode
    let rect: CGRect
    let rank: Int
}

func squarify(_ nodes: [MapNode], in bounds: CGRect) -> [MapTile] {
    let items = nodes.filter { $0.size > 0 }
    let total = items.reduce(0.0) { $0 + Double($1.size) }
    guard total > 0, bounds.width > 1, bounds.height > 1 else { return [] }
    let scale = Double(bounds.width * bounds.height) / total
    var r = bounds
    var row: [(MapNode, Double)] = []
    var tiles: [MapTile] = []

    func worst(_ row: [(MapNode, Double)], _ side: Double) -> Double {
        let s = row.reduce(0) { $0 + $1.1 }
        guard s > 0, side > 0 else { return .infinity }
        return row.map { max(side * side * $0.1 / (s * s), (s * s) / (side * side * $0.1)) }.max() ?? .infinity
    }
    func place(_ row: [(MapNode, Double)]) {
        let s = row.reduce(0) { $0 + $1.1 }
        guard s > 0 else { return }
        if r.width >= r.height {
            let w = CGFloat(s) / r.height
            var y = r.minY
            for (n, a) in row {
                let h = CGFloat(a) / w
                tiles.append(MapTile(node: n, rect: CGRect(x: r.minX, y: y, width: w, height: h), rank: tiles.count))
                y += h
            }
            r = CGRect(x: r.minX + w, y: r.minY, width: max(0, r.width - w), height: r.height)
        } else {
            let hgt = CGFloat(s) / r.width
            var x = r.minX
            for (n, a) in row {
                let w = CGFloat(a) / hgt
                tiles.append(MapTile(node: n, rect: CGRect(x: x, y: r.minY, width: w, height: hgt), rank: tiles.count))
                x += w
            }
            r = CGRect(x: r.minX, y: r.minY + hgt, width: r.width, height: max(0, r.height - hgt))
        }
    }

    for n in items {
        let a = Double(n.size) * scale
        let side = Double(min(r.width, r.height))
        if row.isEmpty || worst(row + [(n, a)], side) <= worst(row, side) {
            row.append((n, a))
        } else {
            place(row)
            row = [(n, a)]
        }
    }
    place(row)
    return tiles
}
