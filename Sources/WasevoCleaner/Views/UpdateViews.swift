import SwiftUI
import AppKit

/// Settings card: automatic checks, "Check now", and the install button with release notes.
struct UpdateCard: View {
    @ObservedObject private var up = SelfUpdate.shared
    @AppStorage("autoUpdateCheck") private var autoCheck = true

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SettingRow("Check for updates automatically", "Once a day, from the official GitHub releases. You choose when to install.") {
                    Toggle("", isOn: $autoCheck).labelsHidden().toggleStyle(.switch).tint(W.orange)
                }
                Divider().overlay(W.line)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You have v\(appVersion)").font(W.body(13, .semibold)).foregroundColor(W.text)
                        Text(statusText).font(W.body(11)).foregroundColor(statusColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if case .downloading(let f) = up.state {
                        ProgressView(value: f).frame(width: 140).tint(W.orange)
                    } else if up.state == .installing || up.state == .checking {
                        ProgressView().controlSize(.small)
                    } else if up.isAvailable {
                        SecondaryButton(title: "Skip", icon: nil) { up.skipThisVersion() }
                        PrimaryButton(title: "Update to v\(up.latest?.version ?? "")", icon: "arrow.down.circle") { up.install() }
                    } else {
                        SecondaryButton(title: "Check now", icon: "arrow.clockwise") { up.check() }
                    }
                }
                if up.isAvailable, let rel = up.latest {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("What's new in v\(rel.version)").font(W.body(12, .semibold)).foregroundColor(W.text)
                            Spacer()
                            Button("Release page") { NSWorkspace.shared.open(rel.page) }
                                .buttonStyle(.link).font(W.body(11))
                        }
                        ScrollView {
                            Text(releaseNotes(rel.notes))
                                .font(W.body(11.5)).foregroundColor(W.muted)
                                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }
                        .frame(maxHeight: 140)
                        Text("Downloaded from GitHub and checked against its SHA-256 before installing. Your settings and history stay. macOS may ask for Full Disk Access again after the update.")
                            .font(W.body(10.5)).foregroundColor(W.faint).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(W.bg))
                }
            }
        }
    }

    var statusText: String {
        switch up.state {
        case .idle: return up.lastCheck.map { "Last checked \(RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()))" } ?? "Not checked yet"
        case .checking: return "Checking GitHub..."
        case .upToDate: return "You're up to date."
        case .available: return "Version \(up.latest?.version ?? "") is available (\(human(up.latest?.size ?? 0)))."
        case .downloading(let f): return "Downloading... \(Int(f * 100))%"
        case .installing: return "Verifying and installing. The app will restart."
        case .failed(let m): return m
        }
    }
    var statusColor: Color {
        switch up.state {
        case .available: return W.orange
        case .failed: return W.red
        case .upToDate: return W.green
        default: return W.faint
        }
    }
}

/// Small banner at the bottom of the sidebar when a new version is out.
struct SidebarUpdateBanner: View {
    @ObservedObject private var up = SelfUpdate.shared
    var body: some View {
        if up.isAvailable, let v = up.latest?.version {
            Button { Nav.shared.open(.settings) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill").foregroundColor(W.orange)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Update available").font(W.body(12, .semibold)).foregroundColor(W.text)
                        Text("Version \(v)").font(W.body(10.5)).foregroundColor(W.faint)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundColor(W.faint)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(W.orange.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(W.orange.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(PressStyle())
            .padding(.bottom, 6)
            .help("Open Settings to install the update")
        }
    }
}

/// Icon-only version for the collapsed sidebar.
struct RailUpdateBadge: View {
    @ObservedObject private var up = SelfUpdate.shared
    var body: some View {
        if up.isAvailable {
            Button { Nav.shared.open(.settings) } label: {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 18)).foregroundColor(W.orange)
            }
            .buttonStyle(PressStyle())
            .help("Update available: version \(up.latest?.version ?? "")")
        }
    }
}

/// GitHub release notes are Markdown: headings become bold lines, links and emphasis render.
func releaseNotes(_ md: String) -> AttributedString {
    guard !md.isEmpty else { return AttributedString("No release notes.") }
    let lines = md.components(separatedBy: "\n").map { line -> String in
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { return "**" + t.drop(while: { $0 == "#" || $0 == " " }) + "**" }
        if t.hasPrefix("- ") || t.hasPrefix("* ") { return "• " + t.dropFirst(2) }
        return line
    }
    let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: lines.joined(separator: "\n"), options: opts)) ?? AttributedString(md)
}
