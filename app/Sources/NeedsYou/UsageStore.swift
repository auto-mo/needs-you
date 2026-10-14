import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published var range: UsageRange = .today
    @Published var sessions: [SessionUsage] = []
    @Published var loading = false
    @Published var loaded = false
    @Published var expanded = Set<String>()
    @Published var showRest = false
    @Published var limits: LimitsInfo?
    @Published var limitsError: String?

    let demo: Bool
    private var generation = 0

    init(demo: Bool = false) {
        self.demo = demo
        if demo { Demo.fill(self) }
    }

    func refreshLimits() {
        if !demo { limits = LimitsReader.read() }
    }

    /// Asks the usage service for live limits (at most once a minute unless forced).
    func fetchLiveLimits(force: Bool) {
        guard !demo else { return }
        Task {
            await LiveLimits.shared.refresh(force: force)
            limitsError = await LiveLimits.shared.lastError
            refreshLimits()
        }
    }

    func load(force: Bool = false) {
        guard !demo else { return }
        refreshLimits()
        fetchLiveLimits(force: force)
        generation += 1
        let gen = generation
        let r = range
        loading = true
        Task {
            let snap = await UsageScanner.shared.snapshot(range: r)
            guard gen == generation else { return }
            sessions = snap.sessions
            loading = false
            loaded = true
        }
    }

    func setRange(_ r: UsageRange) {
        guard r != range else { return }
        range = r
        sessions = []
        loaded = false
        showRest = false
        if demo { Demo.fill(self) } else { load() }
    }

    func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}
