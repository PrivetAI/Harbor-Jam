import SwiftUI
import Combine

/// Why a berth command bounced, and where. The board flashes the reason on the
/// berth the finger was over — one generic shake for every refusal is what made
/// the previous version of this game feel arbitrary rather than difficult.
struct QLRefusalFlash: Equatable {
    var slot: Int
    var reason: QLBerthRefusal
    var stamp: Int

    var message: String {
        switch reason {
        case .tooShallow: return "Too shallow"
        case .occupied: return "Berth taken"
        case .tooLong: return "Will not fit"
        case .channelBusy: return "Channel busy"
        case .outage: return "Berth closed"
        case .notWaiting, .none: return ""
        }
    }
}

/// Owns the simulation and the only clock that drives it.
///
/// The sim never reads wall-clock time — it advances one integer tick per timer
/// fire — so pausing is exact, and the offline harness measures the same rules
/// the player is playing.
final class QLShiftViewModel: ObservableObject {
    @Published private(set) var sim: QLSim
    @Published private(set) var isRunning = false
    @Published var lastRefusal: QLRefusalFlash? = nil

    private var timer: AnyCancellable?

    init(def: QLShiftDef, upgrades: QLUpgradeLevels) {
        sim = QLSim(def: def, upgrades: upgrades)
    }

    deinit { timer?.cancel() }

    func start() {
        guard timer == nil else { return }
        isRunning = true
        timer = Timer.publish(every: 1.0 / Double(QLTuning.tickHz), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.step() }
    }

    func pause() { isRunning = false }

    func resume() { isRunning = !sim.isOver }

    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
    }

    private func step() {
        guard isRunning, !sim.isOver else {
            if sim.isOver { stop() }
            return
        }
        sim.advance()
        // Clear a refusal flash after roughly a second of ticks.
        if let flash = lastRefusal, sim.tick - flash.stamp > QLTuning.tickHz {
            lastRefusal = nil
        }
        if sim.isOver { stop() }
    }

    @discardableResult
    func tryBerth(shipID: Int, atSlot slot: Int) -> QLBerthRefusal {
        let refusal = sim.berth(shipID: shipID, atSlot: slot)
        if refusal != .none {
            lastRefusal = QLRefusalFlash(slot: slot, reason: refusal, stamp: sim.tick)
        }
        return refusal
    }

    @discardableResult
    func send(shipID: Int) -> Bool { sim.depart(shipID: shipID) }

    /// Watch mode only: hands the run its per-wave upgrade.
    func applyUpgrades(_ levels: QLUpgradeLevels) { sim.applyUpgrades(levels) }

    func canBerth(shipID: Int, atSlot slot: Int) -> QLBerthRefusal {
        sim.canBerth(shipID: shipID, atSlot: slot)
    }

    var isOver: Bool { sim.isOver }
    var isFailed: Bool { sim.isFailed }
    var stars: Int { sim.stars() }
    var score: Int { sim.score() }
}
