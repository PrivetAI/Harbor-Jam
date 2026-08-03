import Foundation

/// The rules of Harbor Jam, and the only thing in the codebase allowed to decide
/// a game outcome. Deterministic and integer-only: the same shift definition and
/// the same sequence of commands always produce the same result, which is what
/// lets the offline harness measure the game the player actually gets.
struct HJSim {
    let def: HJShiftDef
    let upgrades: HJUpgradeLevels

    private(set) var tick: Int = 0
    private(set) var ships: [HJShip] = []
    private(set) var reputation: Int
    private(set) var counters = HJSimCounters()
    private(set) var endTick: Int? = nil

    private var pending: [HJArrival]        // not yet arrived, ascending by tick
    private let roadsteadCapacity: Int
    private let penalisesLongShips: Bool

    init(def: HJShiftDef, upgrades: HJUpgradeLevels) {
        self.def = def
        self.upgrades = upgrades
        self.reputation = HJTuning.baseReputation + upgrades.crew
        self.pending = def.arrivals.sorted { $0.tick < $1.tick }
        self.roadsteadCapacity = def.harbor.roadsteadCapacity + upgrades.roadstead
        self.penalisesLongShips = HJCatalog.template(port: def.port)?.longShipTransitPenalty ?? false
    }

    // MARK: - Derived state

    /// Triangle wave over 4·amplitude steps, starting at low water.
    ///
    /// Deliberately not a sine: the player has to be able to count ticks to the
    /// turn of the tide and decide whether a deep hull can get in and out again.
    /// A curve they cannot read turns planning into a gamble.
    func tideOffset(at t: Int) -> Int {
        let a = def.harbor.tideAmplitude
        guard a > 0, def.harbor.tideStepTicks > 0 else { return 0 }
        let steps = 4 * a
        let s = (t / def.harbor.tideStepTicks) % steps
        let up = s <= 2 * a ? s : steps - s
        return up - a
    }

    var tideOffset: Int { tideOffset(at: tick) }

    /// Ticks until the tide changes direction — what the HUD strip counts down.
    func ticksToTideTurn() -> Int {
        let a = def.harbor.tideAmplitude
        guard a > 0, def.harbor.tideStepTicks > 0 else { return 0 }
        let steps = 4 * a
        let step = def.harbor.tideStepTicks
        var t = tick + 1
        let now = tideOffset(at: tick)
        let limit = tick + steps * step + 1
        while t < limit {
            if tideOffset(at: t) != now {
                // Direction only reverses at the crest and the trough.
                let rising = tideOffset(at: t) > now
                var u = t
                while u < limit, (tideOffset(at: u) > tideOffset(at: u - 1)) == rising { u += step }
                return u - tick
            }
            t += 1
        }
        return 0
    }

    func effectiveDepth(slot: Int) -> Int {
        def.harbor.slots[slot].depth + upgrades.dredge + tideOffset
    }

    func isOutOfService(slot: Int) -> Bool {
        def.outages.contains { $0.slot == slot && tick >= $0.startTick && tick < $0.endTick }
    }

    var stormActive: Bool {
        def.storms.contains { tick >= $0.startTick && tick < $0.endTick }
    }

    var occupiedSlots: Set<Int> {
        var out = Set<Int>()
        for s in ships where s.holdsBerth {
            if let r = s.slots { for i in r { out.insert(i) } }
        }
        return out
    }

    var channelBusy: Bool {
        ships.contains { $0.state == .transitingIn || $0.state == .transitingOut }
    }

    var waitingShips: [HJShip] { ships.filter { $0.state == .waiting } }

    var isFailed: Bool { reputation <= 0 }

    var isOver: Bool {
        isFailed || (pending.isEmpty && ships.allSatisfy { $0.state == .served || $0.state == .lost })
    }

    /// Total ships this shift will ever see — the roadstead counter in the HUD.
    var totalShips: Int { ships.count + pending.count }

    // MARK: - Commands

    func canBerth(shipID: Int, atSlot slot: Int) -> HJBerthRefusal {
        guard let ship = ships.first(where: { $0.id == shipID }) else { return .notWaiting }
        guard ship.state == .waiting else { return .notWaiting }
        guard slot >= 0, slot + ship.length <= def.harbor.slots.count else { return .tooLong }
        if channelBusy { return .channelBusy }
        let taken = occupiedSlots
        for i in slot..<(slot + ship.length) {
            if taken.contains(i) { return .occupied }
            if isOutOfService(slot: i) { return .outage }
        }
        for i in slot..<(slot + ship.length) where effectiveDepth(slot: i) < ship.draft {
            return .tooShallow
        }
        return .none
    }

    /// Send a waiting ship to a stretch of quay. She occupies those berths from
    /// this moment — not on arrival — so a second hull cannot be aimed at the
    /// same water while the first is still in the channel.
    @discardableResult
    mutating func berth(shipID: Int, atSlot slot: Int) -> HJBerthRefusal {
        let refusal = canBerth(shipID: shipID, atSlot: slot)
        if refusal == .channelBusy { counters.channelRefusals += 1 }
        guard refusal == .none, let idx = ships.firstIndex(where: { $0.id == shipID })
        else { return refusal }

        var ship = ships[idx]
        ship.berthStart = slot
        ship.state = .transitingIn
        ship.transitLeft = transitTicks(for: ship)
        let matched = def.harbor.slots[slot].equipment == ship.cargo.equipment
        if !matched { counters.mismatchedUnloads += 1 }
        ship.unloadLeft = unloadWork(tons: ship.tons, cargo: ship.cargo, matched: matched)
        ships[idx] = ship
        return .none
    }

    /// Release a finished hull. The berths free the instant she pulls out, but
    /// the channel is hers for the whole transit — which is the entire reason
    /// "free up a berth" is a decision rather than a reflex.
    @discardableResult
    mutating func depart(shipID: Int) -> Bool {
        guard !channelBusy,
              let idx = ships.firstIndex(where: { $0.id == shipID }),
              ships[idx].state == .berthed,
              ships[idx].unloadLeft <= 0
        else { return false }
        var ship = ships[idx]
        ship.state = .transitingOut
        ship.transitLeft = transitTicks(for: ship)
        ship.berthStart = nil
        ships[idx] = ship
        return true
    }

    // MARK: - The tick

    /// Order is normative and both the app and the harness depend on it exactly:
    /// arrivals first, so a ship can be berthed the tick she shows up; grounding
    /// after transits, so a hull that has just moored is judged against the water
    /// she is actually sitting in.
    mutating func advance() {
        guard !isOver else { return }
        tick += 1
        admitArrivals()
        advanceTransits()
        advanceUnloading()
        updateGrounding()
        burnPatience()
        if channelBusy { counters.channelBusyTicks += 1 }
        if isOver && endTick == nil { endTick = tick }
    }

    private mutating func admitArrivals() {
        while let next = pending.first, next.tick <= tick {
            pending.removeFirst()
            var ship = next.ship
            ship.patienceLeft = ship.patienceTicks
            if waitingShips.count >= roadsteadCapacity {
                ship.state = .lost
                ships.append(ship)
                loseReputation()
            } else {
                ship.state = .waiting
                ships.append(ship)
            }
        }
    }

    private mutating func advanceTransits() {
        for i in ships.indices {
            guard ships[i].state == .transitingIn || ships[i].state == .transitingOut else { continue }
            ships[i].transitLeft -= 1
            guard ships[i].transitLeft <= 0 else { continue }
            if ships[i].state == .transitingIn {
                ships[i].state = .berthed
            } else {
                ships[i].state = .served
                counters.shipsServed += 1
                counters.tonsServed += ships[i].tons
                counters.revenue += revenue(for: ships[i])
            }
        }
    }

    private mutating func advanceUnloading() {
        for i in ships.indices where ships[i].state == .berthed || ships[i].state == .aground {
            if ships[i].unloadLeft > 0 { ships[i].unloadLeft -= 2 }
        }
    }

    /// A hull whose water has fallen below her draft is stuck fast: she keeps
    /// unloading but cannot leave, and she keeps every berth she is sitting on.
    private mutating func updateGrounding() {
        for i in ships.indices {
            guard ships[i].state == .berthed || ships[i].state == .aground,
                  let slots = ships[i].slots else { continue }
            let shallow = slots.contains { effectiveDepth(slot: $0) < ships[i].draft }
            if shallow && ships[i].state == .berthed {
                ships[i].state = .aground
                counters.groundings += 1
            } else if !shallow && ships[i].state == .aground {
                ships[i].state = .berthed
            }
        }
    }

    private mutating func burnPatience() {
        let burn = stormActive ? HJTuning.patiencePerTickInStorm : HJTuning.patiencePerTick
        for i in ships.indices where ships[i].state == .waiting {
            ships[i].patienceLeft -= burn
            if ships[i].patienceLeft <= 0 {
                ships[i].state = .lost
                loseReputation()
            }
        }
    }

    private mutating func loseReputation() {
        reputation -= 1
        counters.shipsLost += 1
    }

    // MARK: - Derived numbers

    private func transitTicks(for ship: HJShip) -> Int {
        var t = def.harbor.channelTransitTicks
        t = t * (100 - HJTuning.transitDiscountPerTugLevel * upgrades.tugs) / 100
        if penalisesLongShips && ship.length >= HJTuning.longShipLength {
            t = t * 3 / 2
        }
        return max(1, t)
    }

    private func unloadWork(tons: Int, cargo: HJCargo, matched: Bool) -> Int {
        var w = tons * HJTuning.workPerTon(cargo) * (matched ? 2 : 5)
        w = w * (100 - HJTuning.unloadDiscountPerCraneLevel * upgrades.cranes) / 100
        return max(2, w)
    }

    private func revenue(for ship: HJShip) -> Int {
        ship.tons * HJTuning.rate(ship.cargo) * (ship.isVIP ? HJTuning.vipRateMultiplier : 1)
    }

    /// Revenue plus whatever was saved against par. Speed is in the score on
    /// purpose: a badly packed quay and a carelessly spent channel do not show up
    /// as lost ships, they show up as a shift that drags.
    func score() -> Int {
        let finished = endTick ?? tick
        let speed = max(0, def.parTicks - finished) * HJTuning.speedRate
        return counters.revenue + speed
    }

    func stars() -> Int {
        guard !isFailed, isOver else { return 0 }
        let s = score()
        if s >= def.target3 { return 3 }
        if s >= def.target2 { return 2 }
        return 1
    }
}
