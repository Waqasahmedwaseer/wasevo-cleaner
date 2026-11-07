import SwiftUI

// Space Map: a treemap of your home folder. Click a block to look inside. View only.

final class SpaceMapModel: ObservableObject {
    static let shared = SpaceMapModel()
    @Published var path = home
    @Published var nodes: [MapNode] = []
    @Published var loading = false
    @Published var progress = ""
    private var cache: [String: [MapNode]] = [:]

    var crumbs: [(String, String)] {
        var out = [("Home", home)]
        guard path.hasPrefix(home + "/") else { return out }
        var p = home
        for part in path.dropFirst(home.count + 1).split(separator: "/") {
            p += "/" + part
            out.append((String(part), p))
        }
        return out
    }

    func open(_ p: String, force: Bool = false) {
        path = p
        if !force, let c = cache[p] { nodes = c; return }
        nodes = []
        loading = true
        Activity.shared.start(.map, "Measuring")
        progress = "Measuring…"
        DispatchQueue.global(qos: .userInitiated).async {
            var list = mapChildren(of: p) { done, total in
                DispatchQueue.main.async { if self.path == p { self.progress = "Measuring \(done) of \(total)…" } }
            }
            if p == home {
                let used = volumeTotal() - volumeFree()
                let mine = list.reduce(0) { $0 + $1.size }
                if used > mine {
                    list.append(MapNode(name: "macOS, apps & system", path: "/", size: used - mine, isDir: false, isVirtual: true))
                    list.sort { $0.size > $1.size }
                }
            }
            DispatchQueue.main.async {
                self.cache[p] = list
                if self.path == p { self.nodes = list; self.loading = false }
                Activity.shared.finish(.map, "\((p as NSString).lastPathComponent) measured: \(human(list.reduce(0) { $0 + $1.size })).")
            }
        }
    }

    func up() {
        guard path != home else { return }
        open((path as NSString).deletingLastPathComponent)
    }
}

/// Warm brand palette for the tiles, from deep to light.
let MAP_COLORS: [Color] = [Color(hex: 0xF0561A), Color(hex: 0xF97316), Color(hex: 0xE04E12), Color(hex: 0xFB8C4C),
                           Color(hex: 0xD9480F), Color(hex: 0xFDA172), Color(hex: 0xC2410C), Color(hex: 0xF4793B)]

struct SpaceMapView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var model = SpaceMapModel.shared
    @State private var hovered: String?

    var total: Int64 { model.nodes.reduce(0) { $0 + $1.size } }
    var folderName: String { model.crumbs.last?.0 ?? "Home" }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: "Space Map", subtitle: "Where your disk space goes. Click a block to look inside. View only: nothing is deleted here.") {
                SecondaryButton(title: "Refresh", icon: "arrow.clockwise") { model.open(model.path, force: true) }
            }
            breadcrumb
            HStack(spacing: 14) {
                treemap
                sideList.frame(width: 320)
            }
            .padding(.horizontal, 28).padding(.bottom, 22)
        }
        .onAppear { if model.nodes.isEmpty && !model.loading { model.open(home) } }
    }

    var breadcrumb: some View {
        HStack(spacing: 6) {
            Button { model.up() } label: {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26).background(Circle().fill(W.line))
            }
            .buttonStyle(.plain).foregroundColor(model.path == home ? W.faint.opacity(0.4) : W.text)
            .disabled(model.path == home)
            ForEach(Array(model.crumbs.enumerated()), id: \.offset) { i, c in
                let last = i == model.crumbs.count - 1
                if i > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundColor(W.faint) }
                HStack(spacing: 5) {
                    if i == 0 { Image(systemName: "house").font(.system(size: 10, weight: .semibold)) }
                    Text(c.0).font(W.body(12, last ? .semibold : .regular))
                }
                .foregroundColor(last ? W.text : W.muted)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(last ? W.orange.opacity(0.14) : Color.clear))
                .contentShape(Capsule())
                .onTapGesture { model.open(c.1) }
            }
            Spacer()
            if !model.loading { StatChip(value: human(total), label: "in \(folderName)", color: W.orange300) }
        }
        .padding(.horizontal, 28).padding(.bottom, 12)
        .animation(.spring(response: 0.35), value: model.path)
    }

    var treemap: some View {
        GeometryReader { g in
            let area = CGRect(origin: .zero, size: g.size).insetBy(dx: 6, dy: 6)
            ZStack(alignment: .topLeading) {
                if model.loading {
                    BusyPanel(text: model.progress).frame(width: g.size.width, height: g.size.height)
                } else {
                    let tiles = squarify(Array(model.nodes.prefix(60)), in: area)
                    ForEach(tiles) { t in tile(t).transition(.scale(scale: 0.96).combined(with: .opacity)) }
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.nodes.map(\.id))
        }
        .glassCard(radius: 16)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    func fill(_ t: MapTile) -> LinearGradient {
        let base: Color = t.node.protected != nil ? Color(hex: 0xB42318) : MAP_COLORS[t.rank % MAP_COLORS.count]
        return LinearGradient(colors: [base.opacity(0.78), base], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    func tile(_ t: MapTile) -> some View {
        let r = t.rect.insetBy(dx: 2, dy: 2)
        let big = r.width > 76 && r.height > 40
        let on = hovered == t.id
        let virtual = t.node.isVirtual
        let rad = max(2, min(9, min(r.width, r.height) * 0.22))   // small tiles stay squares, never blobs
        return ZStack(alignment: .topLeading) {
            if virtual {
                RoundedRectangle(cornerRadius: rad).fill(W.panel2)
                    .overlay(RoundedRectangle(cornerRadius: rad).stroke(W.line, lineWidth: 1))
            } else {
                RoundedRectangle(cornerRadius: rad).fill(fill(t))
                    .overlay(RoundedRectangle(cornerRadius: rad).stroke(Color.white.opacity(on ? 0.85 : 0.14), lineWidth: on ? 2 : 1))
            }
            if big {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: virtual ? "applelogo" : t.node.protected != nil ? "lock.fill" : t.node.isDir ? "folder.fill" : "doc.fill")
                            .font(.system(size: 10, weight: .semibold)).opacity(0.85)
                        Text(t.node.name).font(W.body(12, .semibold)).lineLimit(1)
                    }
                    Text(human(t.node.size)).font(W.body(11)).opacity(0.8)
                }
                .foregroundColor(virtual ? W.muted : .white)
                .shadow(color: .black.opacity(virtual ? 0 : 0.18), radius: 2, y: 1)
                .padding(9)
            }
        }
        .frame(width: max(0, r.width), height: max(0, r.height))
        .brightness(on && !virtual ? 0.06 : 0)
        .offset(x: r.minX, y: r.minY)
        .animation(.easeOut(duration: 0.15), value: on)
        .onHover { hovered = $0 ? t.id : (hovered == t.id ? nil : hovered) }
        .onTapGesture { activate(t.node) }
        .help("\(t.node.name) · \(human(t.node.size))\(t.node.protected.map { "\nProtected: \($0)" } ?? "")")
    }

    func activate(_ n: MapNode) {
        if n.isVirtual { return }
        if n.isDir { model.open(n.path) } else { revealInFinder(n.path) }
    }

    var sideList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Biggest in \(folderName)").font(W.body(13, .semibold)).foregroundColor(W.text).lineLimit(1)
                Spacer()
                Text("\(model.nodes.count) items").font(W.body(11)).foregroundColor(W.faint)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            Divider().overlay(W.line)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.nodes.prefix(80).enumerated()), id: \.element.id) { i, n in row(n).staggerIn(i) }
                }
                .padding(8)
            }
            Divider().overlay(W.line)
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 10, weight: .semibold)).foregroundColor(W.red)
                Text("Never deleted").font(W.body(11, .semibold)).foregroundColor(W.muted)
                Text("· To free space, use Smart Scan.").font(W.body(11)).foregroundColor(W.faint).lineLimit(1)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .glassCard(radius: 16)
    }

    func row(_ n: MapNode) -> some View {
        let share = total > 0 ? Double(n.size) / Double(total) : 0
        let on = hovered == n.id
        return HStack(spacing: 10) {
            IconBadge(icon: n.isVirtual ? "applelogo" : n.protected != nil ? "lock.fill" : n.isDir ? "folder.fill" : "doc.fill",
                      color: n.isVirtual ? W.faint : n.protected != nil ? W.red : W.orange, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(n.name).font(W.body(12.5, .medium)).foregroundColor(W.text).lineLimit(1).truncationMode(.middle)
                Text(share >= 0.01 ? "\(Int((share * 100).rounded()))% of \(folderName)" : "under 1%")
                    .font(W.body(10.5)).foregroundColor(W.faint)
            }
            Spacer(minLength: 6)
            Text(human(n.size)).font(W.body(12, .semibold)).foregroundColor(W.muted).monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(alignment: .leading) {
            // share of this folder, drawn as a soft fill behind the row
            GeometryReader { g in
                RoundedRectangle(cornerRadius: 8).fill(W.orange.opacity(on ? 0.16 : 0.07))
                    .frame(width: max(8, g.size.width * CGFloat(share)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(on ? W.line : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? n.id : nil }
        .onTapGesture { activate(n) }
        .contextMenu { if !n.isVirtual { Button("Show in Finder") { revealInFinder(n.path) } } }
    }
}
