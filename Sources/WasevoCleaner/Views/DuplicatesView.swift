import SwiftUI

// Duplicate Finder and Old Downloads. Both are review screens: you pick, files go to the Trash.

enum ToolState { case idle, busy, done }

final class DupModel: ObservableObject {
    static let shared = DupModel()
    @Published var groups: [DupGroup] = []
    @Published var state: ToolState = .idle
    @Published var progress = ""
    @Published var remove: Set<String> = []
    @Published var message: String?
    @Published var keepNewest = false { didSet { selectDefault() } }
    @Published var working = false

    func scan() {
        state = .busy; progress = "Looking through your folders…"; message = nil
        Activity.shared.start(.duplicates, "Finding duplicates")
        DispatchQueue.global(qos: .userInitiated).async {
            let g = findDuplicates(minSize: 1_000_000) { p in DispatchQueue.main.async { self.progress = p } }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.5)) { self.groups = g; self.state = .done }
                Activity.shared.finish(.duplicates, "\(g.count) groups of duplicates found.")
                self.selectDefault()
            }
        }
    }

    /// Selects every copy except one per group (the oldest, or the newest).
    func selectDefault() {
        remove = Set(groups.flatMap { g -> [String] in
            let keep = keepNewest ? g.files.last : g.files.first
            return g.files.filter { $0.path != keep?.path }.map(\.path)
        })
    }

    func toggle(_ f: UserFile, in g: DupGroup) {
        if remove.contains(f.path) { remove.remove(f.path); return }
        let stays = g.files.filter { $0.path != f.path && !remove.contains($0.path) }
        if stays.isEmpty { message = "One copy always stays. Untick another copy first."; return }
        remove.insert(f.path)
    }

    var selectedSize: Int64 { groups.reduce(0) { $0 + Int64($1.files.filter { remove.contains($0.path) }.count) * $1.size } }
    var wasted: Int64 { groups.reduce(0) { $0 + $1.wasted } }

    func trash() {
        working = true
        let snapshot = groups, chosen = remove
        DispatchQueue.global(qos: .userInitiated).async {
            var n = 0
            for g in snapshot {
                let r = chosen.intersection(g.files.map(\.path))
                if !r.isEmpty { n += trashDuplicates(group: g, remove: r) }
            }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.45)) {
                    self.groups = self.groups.compactMap { g in
                        var g = g
                        g.files.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
                        return g.files.count > 1 ? g : nil
                    }
                }
                self.remove = self.remove.filter { FileManager.default.fileExists(atPath: $0) }
                self.message = "\(n) duplicate\(n == 1 ? "" : "s") moved to the Trash. One copy of each file was kept."
                self.working = false
            }
        }
    }
}

struct DuplicatesView: View {
    @ObservedObject private var m = DupModel.shared
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: "Duplicates", subtitle: "Files that are exactly the same, byte for byte, in Downloads, Desktop, Documents, Pictures, Movies and Music.") {
                if m.state == .done { SecondaryButton(title: "Rescan", icon: "arrow.clockwise") { m.scan() } }
            }
            switch m.state {
            case .idle:
                StartPanel(icon: "doc.on.doc", title: "Find duplicate files",
                           text: "Compares file contents (SHA-256), not names. Project folders, app bundles and your Photos library are never looked into.",
                           button: "Find duplicates") { m.scan() }
            case .busy:
                BusyPanel(text: m.progress)
            case .done:
                if m.groups.isEmpty {
                    EmptyState(icon: "checkmark.seal", title: "No duplicates", text: "Every file over 1 MB in your folders is unique.")
                } else {
                    toolbar
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(m.groups.enumerated()), id: \.element.id) { i, g in groupCard(g).staggerIn(i) }
                        }
                        .padding(.horizontal, 28).padding(.bottom, 20)
                    }
                    TrashBar(size: m.selectedSize, count: m.remove.count) { confirm = true }
                }
            }
            if let msg = m.message { Toast(text: msg) { m.message = nil } }
        }
        .animation(.spring(response: 0.4), value: m.message)
        .alert("Move \(m.remove.count) duplicates to the Trash?", isPresented: $confirm) {
            Button("Move to Trash") { m.trash() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each file is checked again right before it moves, and one copy of every file always stays. You can put them back from the Trash.")
        }
    }

    var toolbar: some View {
        HStack(spacing: 10) {
            StatChip(value: "\(m.groups.count)", label: "groups")
            StatChip(value: human(m.wasted), label: "taken by extra copies", color: W.orange300)
            Spacer()
            Text("Keep").font(W.body(12)).foregroundColor(W.faint)
            Picker("", selection: $m.keepNewest) {
                Text("Oldest copy").tag(false); Text("Newest copy").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 220)
        }
        .padding(.horizontal, 28).padding(.bottom, 12)
    }

    func groupCard(_ g: DupGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                FileThumb(path: g.files[0].path, size: 30)
                Text(g.files[0].name).font(W.body(13, .semibold)).foregroundColor(W.text).lineLimit(1)
                Pill(g.kind, W.faint)
                Spacer()
                Text("\(g.files.count) copies · \(human(g.size)) each").font(W.body(11)).foregroundColor(W.faint)
            }
            .padding(14)
            Divider().overlay(W.line)
            ForEach(g.files) { f in
                let on = m.remove.contains(f.path)
                HStack(spacing: 12) {
                    CheckBox(on: on)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.folderLabel).font(W.mono).foregroundColor(on ? W.muted : W.text).lineLimit(1).truncationMode(.middle)
                        Text("Changed \(relativeDate(f.modified))").font(W.body(10)).foregroundColor(W.faint)
                    }
                    Spacer()
                    if !on { Pill("Keeps", W.green) }
                    Button { revealInFinder(f.path) } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.plain).foregroundColor(W.faint).help("Show in Finder")
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(on ? W.orange.opacity(0.05) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { m.toggle(f, in: g) } }
            }
        }
        .glassCard(radius: 14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(W.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Old downloads

final class DownloadsModel: ObservableObject {
    static let shared = DownloadsModel()
    @Published var items: [OldDownload] = []
    @Published var state: ToolState = .idle
    @Published var chosen: Set<String> = []
    @Published var days = 60.0
    @Published var message: String?

    func scan() {
        state = .busy; message = nil
        Activity.shared.start(.downloads, "Checking downloads")
        let d = days
        DispatchQueue.global(qos: .userInitiated).async {
            let list = findOldDownloads(days: d)
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.5)) { self.items = list; self.state = .done }
                Activity.shared.finish(.downloads, "\(list.count) old downloads to review.")
                self.chosen = []
            }
        }
    }

    var size: Int64 { items.filter { chosen.contains($0.path) }.reduce(0) { $0 + $1.size } }

    func trash() {
        let pick = chosen
        DispatchQueue.global(qos: .userInitiated).async {
            let n = pick.filter { trashUserFile($0) }.count
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.45)) { self.items.removeAll { !FileManager.default.fileExists(atPath: $0.path) } }
                self.chosen = []
                self.message = "\(n) item\(n == 1 ? "" : "s") moved to the Trash."
            }
        }
    }
}

struct DownloadsView: View {
    @ObservedObject private var m = DownloadsModel.shared
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: "Old Downloads", subtitle: "Things in your Downloads folder you have not opened in a long time. Nothing is selected for you.") {
                HStack(spacing: 10) {
                    Picker("", selection: $m.days) {
                        Text("30 days").tag(30.0); Text("60 days").tag(60.0); Text("90 days").tag(90.0); Text("6 months").tag(180.0)
                    }
                    .labelsHidden().frame(width: 110)
                    .onChange(of: m.days) { _ in if m.state == .done { m.scan() } }
                    if m.state == .done { SecondaryButton(title: "Rescan", icon: "arrow.clockwise") { m.scan() } }
                }
            }
            switch m.state {
            case .idle:
                StartPanel(icon: "arrow.down.circle", title: "Review old downloads",
                           text: "Installers, zips and files you downloaded and never opened again. Uses macOS's own \"last opened\" date.",
                           button: "Find old downloads") { m.scan() }
            case .busy: BusyPanel(text: "Checking when you last opened each item…")
            case .done:
                if m.items.isEmpty {
                    EmptyState(icon: "checkmark.seal", title: "Downloads look tidy", text: "Nothing over 1 MB that you haven't opened in \(Int(m.days)) days.")
                } else {
                    HStack {
                        StatChip(value: "\(m.items.count)", label: "items")
                        StatChip(value: human(m.items.reduce(0) { $0 + $1.size }), label: "total", color: W.orange300)
                        Spacer()
                        Button(m.chosen.count == m.items.count ? "Select none" : "Select all") {
                            withAnimation { m.chosen = m.chosen.count == m.items.count ? [] : Set(m.items.map(\.path)) }
                        }
                        .buttonStyle(.plain).font(W.body(12, .semibold)).foregroundColor(W.orange300)
                    }
                    .padding(.horizontal, 28).padding(.bottom, 10)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(m.items.enumerated()), id: \.element.id) { i, d in row(d).staggerIn(i); Divider().overlay(W.line) }
                        }
                        .padding(.horizontal, 16)
                    }
                    TrashBar(size: m.size, count: m.chosen.count) { confirm = true }
                }
            }
            if let msg = m.message { Toast(text: msg) { m.message = nil } }
        }
        .animation(.spring(response: 0.4), value: m.message)
        .alert("Move \(m.chosen.count) items to the Trash?", isPresented: $confirm) {
            Button("Move to Trash") { m.trash() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You can put them back from the Trash.") }
    }

    func row(_ d: OldDownload) -> some View {
        let on = m.chosen.contains(d.path)
        return HStack(spacing: 14) {
            CheckBox(on: on)
            FileThumb(path: d.path, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(d.name).font(W.body(13, .semibold)).foregroundColor(W.text).lineLimit(1).truncationMode(.middle)
                Text(d.days > 3650 ? "Never opened" : "Last opened \(d.days) days ago").font(W.body(11)).foregroundColor(W.faint)
            }
            Spacer()
            Button { revealInFinder(d.path) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.plain).foregroundColor(W.faint)
            Text(human(d.size)).font(W.body(13, .semibold)).foregroundColor(W.muted).frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(on ? W.orange.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { if on { m.chosen.remove(d.path) } else { m.chosen.insert(d.path) } } }
    }
}
