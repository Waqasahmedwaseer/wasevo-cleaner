import Foundation
import SwiftUI
import AppKit

// Wasevo Cleaner — background activity. Every scan keeps running when you switch pages; the sidebar
// shows a spinner while it works and a dot when it finished while you were somewhere else.

final class Activity: ObservableObject {
    static let shared = Activity()
    @Published private(set) var running: [Page: String] = [:]   // page → what it is doing
    @Published private(set) var finished: Set<Page> = []         // done while you were on another page
    var current: Page = .scan { didSet { finished.remove(current) } }

    func start(_ p: Page, _ what: String) {
        onMain { self.running[p] = what; self.finished.remove(p) }
    }

    /// Marks a task done. If you are on another page, the sidebar gets a dot and macOS shows a notification.
    func finish(_ p: Page, _ summary: String) {
        onMain {
            self.running[p] = nil
            guard self.current != p else { return }
            self.finished.insert(p)
            notify("\(p.rawValue) finished", summary)
        }
    }

    private func onMain(_ f: @escaping () -> Void) { Thread.isMainThread ? f() : DispatchQueue.main.async(execute: f) }
}
