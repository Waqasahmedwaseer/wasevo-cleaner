import SwiftUI
import QuickLook

/// Quick Look preview for any file the app lists (photos, duplicates, downloads, large files).
/// Opening a file with siblings lets the arrow keys step through the whole group.
final class Preview: ObservableObject {
    static let shared = Preview()
    @Published var url: URL?
    @Published var items: [URL] = []

    func open(_ path: String, in group: [String] = []) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return }
        let list = (group.isEmpty ? [path] : group).filter { fm.fileExists(atPath: $0) }
        items = list.map { URL(fileURLWithPath: $0) }
        url = URL(fileURLWithPath: path)
    }
}

/// Opens a file in Quick Look (with optional siblings to browse with the arrow keys).
func quickLook(_ path: String, in group: [String] = []) { Preview.shared.open(path, in: group) }

/// Attached once to the main window so every page can open a preview.
struct QuickLookHost: ViewModifier {
    @ObservedObject private var preview = Preview.shared
    func body(content: Content) -> some View {
        content.quickLookPreview($preview.url, in: preview.items)
    }
}

/// Small eye button used next to "Show in Finder" in file lists.
struct PreviewButton: View {
    let path: String
    var group: [String] = []
    @State private var hover = false
    var body: some View {
        Button { quickLook(path, in: group) } label: { Image(systemName: "eye") }
            .buttonStyle(.plain)
            .foregroundColor(hover ? W.orange : W.faint)
            .onHover { hover = $0 }
            .help("Preview (Quick Look)")
    }
}
