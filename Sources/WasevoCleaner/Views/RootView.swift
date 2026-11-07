import SwiftUI

// App shell: native split view (sidebar + page) with a real window toolbar:
// back / forward, page title and the appearance switch live in the toolbar.

enum Page: String, CaseIterable, Identifiable {
    case scan = "Smart Scan", map = "Space Map", projects = "Projects", duplicates = "Duplicates"
    case photos = "Photo Cleaner", downloads = "Old Downloads", uninstaller = "Uninstaller"
    case privacy = "Browser Privacy", startup = "Startup Items", monitor = "System Monitor"
    case maintenance = "Maintenance", updates = "App Updates"
    case large = "Large Files", protected = "Protected", history = "History", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .scan: return "sparkles"
        case .map: return "square.grid.2x2"
        case .projects: return "folder"
        case .uninstaller: return "trash.square"
        case .duplicates: return "doc.on.doc"
        case .photos: return "photo.stack"
        case .downloads: return "arrow.down.circle"
        case .privacy: return "hand.raised"
        case .startup: return "power"
        case .monitor: return "waveform.path.ecg"
        case .maintenance: return "wrench.and.screwdriver"
        case .updates: return "arrow.triangle.2.circlepath"
        case .large: return "doc.text.magnifyingglass"
        case .protected: return "lock.shield"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
    /// Each module has its own colour world (like CleanMyMac): sidebar icon, glossy header icon, backdrop glow.
    var tint: Color {
        switch self {
        case .scan: return Color(hex: 0xFD5E15)
        case .map: return Color(hex: 0x8B5CF6)
        case .projects: return Color(hex: 0x6366F1)
        case .duplicates: return Color(hex: 0x14B8A6)
        case .photos: return Color(hex: 0xEC4899)
        case .downloads: return Color(hex: 0x0EA5E9)
        case .uninstaller: return Color(hex: 0x3B82F6)
        case .privacy: return Color(hex: 0xD946EF)
        case .startup: return Color(hex: 0xF59E0B)
        case .monitor: return Color(hex: 0x22C55E)
        case .maintenance: return Color(hex: 0x06B6D4)
        case .updates: return Color(hex: 0x2563EB)
        case .large: return Color(hex: 0xF97316)
        case .protected: return Color(hex: 0xEF4444)
        case .history, .settings: return Color(hex: 0x64748B)
        }
    }
    var section: String {
        switch self {
        case .scan, .map, .projects, .duplicates, .photos, .downloads, .uninstaller: return "CLEAN"
        case .privacy, .startup, .monitor, .maintenance, .updates: return "OPTIMIZE"
        case .large, .protected: return "INSPECT"
        case .history, .settings: return "APP"
        }
    }
}

struct SidebarItem: View {
    let page: Page
    let selected: Bool
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hover = false
    @ObservedObject private var act = Activity.shared
    var body: some View {
        HStack(spacing: 10) {
            // small glossy colour chip per module, like the system Settings sidebar
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [page.tint.opacity(0.85), page.tint], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)))
                .overlay(Image(systemName: page.icon).font(.system(size: 11, weight: .semibold)).foregroundColor(.white))
                .frame(width: 22, height: 22)
                .shadow(color: page.tint.opacity(0.35), radius: 3, y: 1)
            Text(page.rawValue).font(W.body(13, selected ? .semibold : .regular))
            Spacer()
            if act.running[page] != nil {
                ProgressView().controlSize(.mini).help(act.running[page] ?? "")
                    .transition(.scale.combined(with: .opacity))
            } else if act.finished.contains(page) {
                Circle().fill(page.tint).frame(width: 7, height: 7).help("Finished")
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: act.running[page] != nil)
        .animation(.spring(response: 0.3), value: act.finished.contains(page))
        .foregroundColor(selected || hover ? W.text : W.muted)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(page.tint.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(page.tint.opacity(0.22), lineWidth: 1))
                    .matchedGeometryEffect(id: "sidebar-selection", in: ns)
            } else if hover {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(W.line)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var page: Page = .scan
    @State private var back: [Page] = []
    @State private var forward: [Page] = []
    @Namespace private var ns
    @AppStorage("appearance") private var appearance = AppAppearance.light.rawValue

    func go(_ p: Page, record: Bool = true) {
        guard p != page else { return }
        if record { back.append(page); forward.removeAll() }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { page = p }
        Activity.shared.current = p
    }
    @ObservedObject private var act = Activity.shared

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 214, ideal: 224, max: 260)
        } detail: {
            detail
                .id(page)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Backdrop())
                .environment(\.pageTint, page.tint)
                .environment(\.pageIcon, page.icon)
                .navigationTitle(page.rawValue)
                .toolbar { toolbar }
                .modifier(SeeThroughToolbar())
        }
        .frame(minWidth: 1040, minHeight: 680)
        .onChange(of: appearance) { v in AppAppearance(rawValue: v)?.apply() }
        .onAppear {
            AppAppearance.current.apply()
            // `--scan` starts a Smart Scan on launch (handy for scripts and screenshots)
            if CommandLine.arguments.contains("--scan") && store.phase == .idle { store.scan() }
        }
    }

    @ViewBuilder var detail: some View {
        switch page {
        case .scan: ScanView()
        case .map: SpaceMapView()
        case .projects: ProjectsView()
        case .uninstaller: UninstallerView()
        case .duplicates: DuplicatesView()
        case .photos: PhotosView()
        case .downloads: DownloadsView()
        case .privacy: PrivacyView()
        case .startup: StartupView()
        case .monitor: MonitorView()
        case .maintenance: MaintenanceView()
        case .updates: UpdatesView()
        case .large: LargeFilesView()
        case .protected: ProtectedView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }

    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                guard let p = back.popLast() else { return }
                forward.append(page); go(p, record: false)
            } label: { Image(systemName: "chevron.left") }
            .disabled(back.isEmpty).help("Back").keyboardShortcut("[", modifiers: .command)
            Button {
                guard let p = forward.popLast() else { return }
                back.append(page); go(p, record: false)
            } label: { Image(systemName: "chevron.right") }
            .disabled(forward.isEmpty).help("Forward").keyboardShortcut("]", modifiers: .command)
        }
        ToolbarItem(placement: .primaryAction) {
            if let (p, what) = act.running.first {
                Button { go(p) } label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(act.running.count > 1 ? "\(act.running.count) tasks running" : "\(what)…").font(W.body(11.5, .medium))
                    }
                }
                .help("Running in the background. Click to open.")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases, id: \.self) { a in
                    Label(a.rawValue, systemImage: a.icon).tag(a.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Appearance: Light, Dark or follow your Mac")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { go(.settings) } label: { Image(systemName: "gearshape") }.help("Settings")
        }
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Logo(size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Wasevo").font(W.display(17)).foregroundColor(W.text).fixedSize()
                    Text("CLEANER").font(.system(size: 9.5, weight: .bold)).tracking(2.5).foregroundColor(W.orange).fixedSize()
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(["CLEAN", "OPTIMIZE", "INSPECT", "APP"], id: \.self) { sec in
                        Text(sec).font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundColor(W.faint)
                            .padding(.horizontal, 10).padding(.top, sec == "CLEAN" ? 0 : 10).padding(.bottom, 3)
                        ForEach(Page.allCases.filter { $0.section == sec }) { p in
                            SidebarItem(page: p, selected: page == p, ns: ns) { go(p) }
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            diskMini
        }
        .padding(.horizontal, 10).padding(.bottom, 14)
    }

    var diskMini: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "internaldrive").foregroundColor(W.faint)
                Text("Macintosh HD").font(W.body(11, .semibold)).foregroundColor(W.muted)
                Spacer()
                Text("\(Int(store.usedFraction * 100))%").font(W.body(11, .bold)).foregroundColor(store.isLow ? W.red : W.orange300)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(W.line)
                    Capsule().fill(store.isLow ? AnyShapeStyle(W.red) : AnyShapeStyle(W.accent)).frame(width: g.size.width * store.usedFraction)
                }
            }
            .frame(height: 6)
            Text("\(human(store.free)) free of \(human(store.total))").font(W.body(11)).foregroundColor(store.isLow ? W.red : W.faint)
        }
        .padding(12)
        .glassCard(radius: 12)
    }
}

/// Lets the coloured backdrop flow under the toolbar (macOS 15+); macOS 26 draws Liquid Glass there.
struct SeeThroughToolbar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) { content.toolbarBackground(.hidden, for: .windowToolbar) } else { content }
    }
}
