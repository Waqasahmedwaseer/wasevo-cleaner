import SwiftUI

// Photo Cleaner: similar shots (the sharpest one is kept) and blurry / dark / overexposed camera photos.

final class PhotosModel: ObservableObject {
    static let shared = PhotosModel()
    @Published var similar: [PhotoGroup] = []
    @Published var bad: [PhotoInfo] = []
    @Published var state: ToolState = .idle
    @Published var progress = ""
    @Published var chosen: Set<String> = []
    @Published var tab = 0
    @Published var message: String?

    func scan() {
        state = .busy; message = nil
        Activity.shared.start(.photos, "Scanning photos")
        DispatchQueue.global(qos: .userInitiated).async {
            let r = analyzePhotos { p in DispatchQueue.main.async { self.progress = p } }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.5)) { self.similar = r.similar; self.bad = r.bad; self.state = .done }
                Activity.shared.finish(.photos, "\(r.similar.count) groups of similar photos, \(r.bad.count) to review.")
                // camera-photo groups: everything except the sharpest is pre-selected.
                // screenshot/graphic groups and bad photos: nothing pre-selected, you decide.
                self.chosen = Set(r.similar.filter { $0.photos.allSatisfy(\.isCameraPhoto) }
                    .flatMap { $0.photos.dropFirst().map(\.file.path) })
            }
        }
    }

    func toggle(_ p: PhotoInfo, group: PhotoGroup?) {
        if chosen.contains(p.id) { chosen.remove(p.id); return }
        if let g = group, g.photos.filter({ $0.id != p.id && !chosen.contains($0.id) }).isEmpty {
            message = "One photo of each group always stays."; return
        }
        chosen.insert(p.id)
    }

    var all: [PhotoInfo] { similar.flatMap(\.photos) + bad }
    var size: Int64 { Set(all.filter { chosen.contains($0.id) }.map(\.file)).reduce(0) { $0 + $1.size } }

    func trash() {
        let pick = chosen
        DispatchQueue.global(qos: .userInitiated).async {
            let n = pick.filter { trashUserFile($0) }.count
            DispatchQueue.main.async {
                let fm = FileManager.default
                withAnimation(.spring(response: 0.45)) {
                    self.similar = self.similar.compactMap { g in
                        let left = g.photos.filter { fm.fileExists(atPath: $0.file.path) }
                        return left.count > 1 ? PhotoGroup(photos: left) : nil
                    }
                    self.bad.removeAll { !fm.fileExists(atPath: $0.file.path) }
                }
                self.chosen = self.chosen.filter { fm.fileExists(atPath: $0) }
                self.message = "\(n) photo\(n == 1 ? "" : "s") moved to the Trash."
            }
        }
    }
}

struct PhotosView: View {
    @ObservedObject private var m = PhotosModel.shared
    @State private var confirm = false
    private let cols = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: "Photo Cleaner", subtitle: "Similar shots and blurry, dark or overexposed photos in your folders. Your Apple Photos library is never touched.") {
                if m.state == .done { SecondaryButton(title: "Rescan", icon: "arrow.clockwise") { m.scan() } }
            }
            switch m.state {
            case .idle:
                StartPanel(icon: "photo.stack", title: "Tidy up your photos",
                           text: "Apple's Vision framework compares your photos on this Mac. Nothing is uploaded. For similar shots, the sharpest one is kept.",
                           button: "Scan photos") { m.scan() }
            case .busy: BusyPanel(text: m.progress)
            case .done:
                Picker("", selection: $m.tab) {
                    Text("Similar shots (\(m.similar.count))").tag(0)
                    Text("Blurry, dark & overexposed (\(m.bad.count))").tag(1)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 460).padding(.bottom, 12)
                ScrollView {
                    if m.tab == 0 { similarList } else { badGrid }
                }
                .animation(.spring(response: 0.4), value: m.tab)
                TrashBar(size: m.size, count: m.chosen.count) { confirm = true }
            }
            if let msg = m.message { Toast(text: msg) { m.message = nil } }
        }
        .animation(.spring(response: 0.4), value: m.message)
        .alert("Move \(m.chosen.count) photos to the Trash?", isPresented: $confirm) {
            Button("Move to Trash") { m.trash() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You can put them back from the Trash.") }
    }

    @ViewBuilder var similarList: some View {
        if m.similar.isEmpty {
            EmptyState(icon: "checkmark.seal", title: "No similar shots", text: "No near-identical photos were found.").frame(height: 340)
        } else {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(Array(m.similar.enumerated()), id: \.element.id) { i, g in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(g.photos.count) similar photos").font(W.body(12, .semibold)).foregroundColor(W.faint)
                        LazyVGrid(columns: cols, alignment: .leading, spacing: 12) {
                            ForEach(Array(g.photos.enumerated()), id: \.element.id) { j, p in tile(p, best: j == 0, group: g) }
                        }
                    }
                    .padding(14)
                    .glassCard(radius: 14)
                    .staggerIn(i)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 20)
        }
    }

    @ViewBuilder var badGrid: some View {
        if m.bad.isEmpty {
            EmptyState(icon: "checkmark.seal", title: "No bad photos", text: "No blurry, very dark or overexposed camera photos were found.").frame(height: 340)
        } else {
            LazyVGrid(columns: cols, alignment: .leading, spacing: 12) {
                ForEach(Array(m.bad.enumerated()), id: \.element.id) { i, p in tile(p, best: false, group: nil).staggerIn(i) }
            }
            .padding(.horizontal, 28).padding(.bottom, 20)
        }
    }

    func tile(_ p: PhotoInfo, best: Bool, group: PhotoGroup?) -> some View {
        let on = m.chosen.contains(p.id)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                FileThumb(path: p.file.path, size: 150)
                    .overlay(RoundedRectangle(cornerRadius: 27).stroke(on ? W.orange : Color.clear, lineWidth: 3))
                    .opacity(on ? 0.75 : 1)
                CheckBox(on: on).padding(8)
                if best { Pill("Sharpest · keeps", W.green).padding(8).frame(maxWidth: .infinity, alignment: .trailing) }
                if let issue = p.issue, group == nil { Pill(issue.rawValue, W.amber).padding(8).frame(maxWidth: .infinity, alignment: .trailing) }
            }
            .frame(width: 150, height: 150)
            .scaleEffect(on ? 0.97 : 1)
            Text(p.file.name).font(W.body(11, .semibold)).foregroundColor(W.text).lineLimit(1).truncationMode(.middle)
            Text(human(p.file.size)).font(W.body(10)).foregroundColor(W.faint)
        }
        .frame(width: 150)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.25)) { m.toggle(p, group: group) } }
        .contextMenu { Button("Show in Finder") { revealInFinder(p.file.path) } }
    }
}
