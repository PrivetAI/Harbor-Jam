import Foundation

enum ForgePolicy: String { case greedy = "G", random = "R", smart = "S" }

struct ForgeResult {
    var score: Int
    var stars: Int
    var failed: Bool
    var endTick: Int
    var counters: QLSimCounters
}

/// A shift that has not finished by here is stalled, not hard. The gate treats
/// hitting this cap as a bug to fix rather than a measurement.
let forgeTickCap = 20_000

func forgeRun(def: QLShiftDef, upgrades: QLUpgradeLevels,
              policy: ForgePolicy, seed: UInt64) -> ForgeResult {
    var sim = QLSim(def: def, upgrades: upgrades)
    var rng = ForgeRNG(seed: seed)
    var guardTicks = 0

    while !sim.isOver && guardTicks < forgeTickCap {
        guardTicks += 1
        applyDepartures(&sim, policy: policy)
        applyBerthing(&sim, policy: policy, rng: &rng)
        sim.advance()
    }
    return ForgeResult(score: sim.score(), stars: sim.stars(), failed: sim.isFailed,
                       endTick: guardTicks, counters: sim.counters)
}

private func applyDepartures(_ sim: inout QLSim, policy: ForgePolicy) {
    guard !sim.channelBusy else { return }
    guard let first = sim.ships.first(where: { $0.state == .berthed && $0.unloadLeft <= 0 })
    else { return }

    switch policy {
    case .greedy, .random:
        sim.depart(shipID: first.id)
    case .smart:
        // Hold the channel when a waiting hull is nearly out of patience and
        // there is somewhere to put her right now: sending costs the channel,
        // and a lost ship costs reputation, which is worth more.
        let urgent = sim.waitingShips.contains { ship in
            ship.patienceLeft < 240 && hasLegalBerth(sim: sim, ship: ship)
        }
        if !urgent { sim.depart(shipID: first.id) }
    }
}

private func hasLegalBerth(sim: QLSim, ship: QLShip) -> Bool {
    let quay = sim.def.harbor.slots.count
    guard ship.length <= quay else { return false }
    for slot in 0...(quay - ship.length) where sim.canBerth(shipID: ship.id, atSlot: slot) == .none {
        return true
    }
    return false
}

private func applyBerthing(_ sim: inout QLSim, policy: ForgePolicy, rng: inout ForgeRNG) {
    guard !sim.channelBusy else { return }
    let quay = sim.def.harbor.slots.count

    switch policy {
    case .greedy:
        // First waiting ship, first slot that fits. This is the policy the gate
        // has to defeat: if it three-stars the corpus, there is no puzzle here.
        for ship in sim.waitingShips {
            guard ship.length <= quay else { continue }
            for slot in 0...(quay - ship.length)
            where sim.canBerth(shipID: ship.id, atSlot: slot) == .none {
                sim.berth(shipID: ship.id, atSlot: slot)
                return
            }
        }

    case .random:
        let waiting = sim.waitingShips
        guard !waiting.isEmpty else { return }
        let ship = waiting[rng.int(waiting.count)]
        guard ship.length <= quay else { return }
        let legal = (0...(quay - ship.length)).filter {
            sim.canBerth(shipID: ship.id, atSlot: $0) == .none
        }
        guard !legal.isEmpty else { return }
        sim.berth(shipID: ship.id, atSlot: legal[rng.int(legal.count)])

    case .smart:
        var best: (ship: Int, slot: Int, cost: Int)? = nil
        let taken = sim.occupiedSlots
        for ship in sim.waitingShips.sorted(by: { $0.patienceLeft < $1.patienceLeft }) {
            guard ship.length <= quay else { continue }
            for slot in 0...(quay - ship.length) {
                guard sim.canBerth(shipID: ship.id, atSlot: slot) == .none else { continue }
                var cost = 0
                // Best fit: prefer a gap this hull nearly fills, so the long
                // hulls still have somewhere to go later.
                cost += gapWaste(slot: slot, length: ship.length, quay: quay, taken: taken) * 10
                // Matching gear is worth far more than a tidy quay.
                if sim.def.harbor.slots[slot].equipment != ship.cargo.equipment { cost += 60 }
                // Do not park a deep hull where the falling tide will strand her.
                if wouldGround(sim: sim, ship: ship, slot: slot) { cost += 120 }
                if best == nil || cost < best!.cost { best = (ship.id, slot, cost) }
            }
        }
        if let b = best { sim.berth(shipID: b.ship, atSlot: b.slot) }
    }
}

/// Free berths stranded on either side of a hull placed at `slot`, counting only
/// runs too short to take the longest hull the game produces.
private func gapWaste(slot: Int, length: Int, quay: Int, taken: Set<Int>) -> Int {
    var waste = 0
    var left = slot - 1
    var run = 0
    while left >= 0 && !taken.contains(left) { run += 1; left -= 1 }
    if (1...4).contains(run) { waste += run }
    var right = slot + length
    run = 0
    while right < quay && !taken.contains(right) { run += 1; right += 1 }
    if (1...4).contains(run) { waste += run }
    return waste
}

/// Will the water under this berth fall below the hull's draft before she can
/// finish unloading and get back out through the channel?
private func wouldGround(sim: QLSim, ship: QLShip, slot: Int) -> Bool {
    guard sim.def.harbor.tideAmplitude > 0, sim.def.harbor.tideStepTicks > 0 else { return false }
    let work = ship.tons * QLTuning.workPerTon(ship.cargo) * 5 / 2
    let horizon = sim.tick + work / 2 + sim.def.harbor.channelTransitTicks * 2
    let depth = sim.def.harbor.slots[slot..<(slot + ship.length)].map { $0.depth }.min() ?? 0
    var t = sim.tick
    while t < horizon {
        if depth + sim.upgrades.dredge + sim.tideOffset(at: t) < ship.draft { return true }
        t += sim.def.harbor.tideStepTicks
    }
    return false
}
