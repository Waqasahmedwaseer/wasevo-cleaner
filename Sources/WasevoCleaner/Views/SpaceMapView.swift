import SwiftUI

// Space Map: a treemap of your home folder. Click a block to look inside. View only.

final class SpaceMapModel: ObservableObject {
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
            }
        }
    }

    func up() {
        guard path != home else { return }
        open((path as NSString).deletingLastPathComponent)
    }
}

let MAP_COLORS: [Color] = [Color(hex: 0xFD5E15), Color(hex: 0xE54E0A), Color(hex: 0xC2410C), Color(hex: 0xFB923C),
                           Color(hex: 0x9A3412), Color(hex: 0xFFA274), Color(hex: 0x7C2D12), Color(hex: 0xEA580C)]

struct SpaceMapView: View {
    @EnvironmentObject var store: Store
    @StateObject private var model = SpaceMapModel()
    @State private var hovered: String?

    var total: Int64 { model.nodes.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                PageHeader(title: "Space Map", subtitle: "Where your disk space goes. Click a block to look inside. View only: nothing is deleted here.")
                SecondaryButton(title: "Refresh", icon: "arrow.clockwise") { model.open(model.path, force: true) }
                    .padding(.trailing, 28).padding(.bottom, 14)
            }
            breadcrumb
            HStack(spacing: 16) {
                treemap
                sideList.frame(width: 300)
            }
            .padding(.horizontal, 28).padding(.bottom, 22)
        }
        .onAppear { if model.nodes.isEmpty && !model.loading { model.open(home) } }
    }

    var breadcrumb: some View {
        HStack(spacing: 6) {
            Button { model.up() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).foregroundColor(model.path == home ? W.faint.opacity(0.4) : W.text)
                .disabled(model.path == home)
            ForEach(Array(model.crumbs.enumerated()), id: \.offset) { i, c in
                if i > 0 { Image(systemName: "chevron.right").font(.system(size: 9)).foregroundColor(W.faint) }
                Text(c.0).font(W.body(12, i == model.crumbs.count - 1 ? .semibold : .regular))
                    .foregroundColor(i == model.crumbs.count - 1 ? W.text : W.muted)
                    .onTapGesture { model.open(c.1) }
            }
            Spacer()
            if !model.loading { Text(human(total)).font(W.body(12, .semibold)).foregroundColor(W.orange) }
        }
        .padding(.horizontal, 28).padding(.bottom, 10)
    }

    var treemap: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14).fill(W.panel)
                if model.loading {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.large)
                        Text(model.progress).font(W.body(12)).foregroundColor(W.faint)
                    }
                    .frame(width: g.size.width, height: g.size.height)
                } else {
                    let tiles = squarify(Array(model.nodes.prefix(60)), in: CGRect(origin: .zero, size: g.size))
                    ForEach(tiles) { t in tile(t) }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    func color(_ t: MapTile) -> Color {
        if t.node.isVirtual { return W.panel2 }
        if t.node.protected != nil { return Color(hex: 0x7F1D1D) }
        return MAP_COLORS[t.rank % MAP_COLORS.count].opacity(t.node.isDir ? 1 : 0.7)
    }

    func tile(_ t: MapTile) -> some View {
        let r = t.rect.insetBy(dx: 1.5, dy: 1.5)
        let big = r.width > 70 && r.height > 34
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(color(t))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(hovered == t.id ? 0.9 : 0), lineWidth: 2))
            if big {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        if t.node.protected != nil { Image(systemName: "lock.fill").font(.system(size: 9)) }
                        Text(t.node.name).font(W.body(11, .semibold)).lineLimit(1)
                    }
                    Text(human(t.node.size)).font(W.body(10)).opacity(0.85)
                }
                .foregroundColor(.white).padding(6)
            }
        }
        .frame(width: max(0, r.width), height: max(0, r.height))
        .offset(x: r.minX, y: r.minY)
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
            Text("Biggest here").font(W.body(12, .semibold)).foregroundColor(W.faint).padding(14)
            Divider().overlay(W.line)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.nodes.prefix(80)) { n in
                        HStack(spacing: 10) {
                            Image(systemName: n.isVirtual ? "applelogo" : n.protected != nil ? "lock.fill" : n.isDir ? "folder.fill" : "doc.fill")
                                .foregroundColor(n.protected != nil ? W.red : W.orange300).frame(width: 16)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(n.name).font(W.body(12, .medium)).foregroundColor(W.text).lineLimit(1).truncationMode(.middle)
                                GeometryReader { g in
                                    Capsule().fill(W.orange.opacity(0.8))
                                        .frame(width: g.size.width * CGFloat(Double(n.size) / Double(max(1, model.nodes.first?.size ?? 1))))
                                }
                                .frame(height: 3)
                            }
                            Text(human(n.size)).font(W.body(11, .semibold)).foregroundColor(W.muted).frame(width: 64, alignment: .trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(hovered == n.id ? W.panel2 : Color.clear)
                        .contentShape(Rectangle())
                        .onHover { hovered = $0 ? n.id : nil }
                        .onTapGesture { activate(n) }
                        .contextMenu {
                            if !n.isVirtual { Button("Show in Finder") { revealInFinder(n.path) } }
                        }
                    }
                }
            }
            Divider().overlay(W.line)
            Text("To free space, use Smart Scan. 🔒 = never delete.").font(W.body(11)).foregroundColor(W.faint).padding(12)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(W.panel))
    }
}
