import SwiftUI

// App shell: branded sidebar + page.

enum Page: String, CaseIterable, Identifiable {
    case scan = "Smart Scan", map = "Space Map", projects = "Projects", uninstaller = "Uninstaller"
    case large = "Large Files", protected = "Protected", history = "History", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .scan: return "sparkles"
        case .map: return "square.grid.2x2"
        case .projects: return "folder"
        case .uninstaller: return "trash.square"
        case .large: return "doc.text.magnifyingglass"
        case .protected: return "lock.shield"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var page: Page = .scan

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Group {
                switch page {
                case .scan: ScanView()
                case .map: SpaceMapView()
                case .projects: ProjectsView()
                case .uninstaller: UninstallerView()
                case .large: LargeFilesView()
                case .protected: ProtectedView()
                case .history: HistoryView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(W.bg)
        }
        .frame(minWidth: 980, minHeight: 640)
        .preferredColorScheme(.dark)
        .onAppear {
            // `--scan` starts a Smart Scan on launch (handy for scripts and screenshots)
            if CommandLine.arguments.contains("--scan") && store.phase == .idle { store.scan() }
        }
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Logo(size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Wasevo").font(W.display(18)).foregroundColor(W.text)
                    Text("CLEANER").font(.system(size: 10, weight: .bold)).tracking(2.5).foregroundColor(W.orange)
                }
            }
            .padding(.horizontal, 14).padding(.top, 34).padding(.bottom, 22)

            ForEach(Page.allCases) { p in
                HStack(spacing: 12) {
                    Image(systemName: p.icon).font(.system(size: 15, weight: .semibold)).frame(width: 20)
                    Text(p.rawValue).font(W.body(13, .semibold))
                    Spacer()
                }
                .foregroundColor(page == p ? .white : W.muted)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(page == p ? W.orange : Color.clear))
                .contentShape(Rectangle())
                .onTapGesture { page = p }
            }
            Spacer()
            diskMini
        }
        .padding(.horizontal, 12).padding(.bottom, 16)
        .frame(width: 210)
        .background(W.panel)
        .overlay(Rectangle().fill(W.line).frame(width: 1), alignment: .trailing)
    }

    var diskMini: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "internaldrive").foregroundColor(W.faint)
                Text("Macintosh HD").font(W.body(11, .semibold)).foregroundColor(W.muted)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(W.panel2)
                    Capsule().fill(store.isLow ? W.red : W.orange).frame(width: g.size.width * store.usedFraction)
                }
            }
            .frame(height: 6)
            Text("\(human(store.free)) free of \(human(store.total))").font(W.body(11)).foregroundColor(store.isLow ? W.red : W.faint)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(W.bg.opacity(0.6)))
    }
}
