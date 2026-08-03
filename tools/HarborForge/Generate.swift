import Foundation

/// SplitMix64 — identical sequences across runs and machines for a given seed.
struct ForgeRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func int(_ upper: Int) -> Int {
        upper <= 0 ? 0 : Int(next() % UInt64(upper))
    }
    mutating func inRange(_ r: ClosedRange<Int>) -> Int {
        r.lowerBound + int(r.upperBound - r.lowerBound + 1)
    }
    mutating func pick<T>(_ xs: [T]) -> T { xs[int(xs.count)] }
}

func forgeSeed(port: Int, shift: Int, salt: Int) -> UInt64 {
    UInt64(0x484A) &* 0x9E3779B97F4A7C15
        &+ UInt64(port) &* 7919 &+ UInt64(shift) &* 104729 &+ UInt64(salt) &* 1_000_003
}

func forgeHarbor(template t: HJPortTemplate, rng: inout ForgeRNG) -> HJHarborDef {
    // Equipment is dealt round-robin and then shuffled, not drawn independently
    // per slot. Independent draws leave whole cargo types with one berth or none
    // on some seeds, which is not a hard shift — it is an unfair one, and the
    // player cannot tell the two apart.
    var gear: [HJEquipment] = []
    for i in 0..<t.slotCount { gear.append(t.equipment[i % t.equipment.count]) }
    for i in stride(from: gear.count - 1, to: 0, by: -1) {
        gear.swapAt(i, rng.int(i + 1))
    }

    var slots: [HJSlot] = []
    for i in 0..<t.slotCount {
        slots.append(HJSlot(depth: rng.inRange(t.depthRange), equipment: gear[i]))
    }
    return HJHarborDef(slots: slots,
                       channelTransitTicks: t.channelTransitTicks,
                       tideAmplitude: t.tideAmplitude,
                       tideStepTicks: t.tideStepTicks,
                       roadsteadCapacity: 4)
}

/// Arrivals are generated FORWARD — a stream of plausible ships, with no notion
/// of a solution. Nothing here consults a target answer, which is the structural
/// difference from the previous generator: that one built levels by undoing a
/// solution and then discarded every seed where a mechanic would have mattered.
func forgeArrivals(template t: HJPortTemplate, harbor: HJHarborDef,
                   rng: inout ForgeRNG) -> [HJArrival] {
    let count = rng.inRange(t.shipCount)
    let maxUsableDepth = (harbor.slots.map { $0.depth }.max() ?? 5) + t.tideAmplitude
    var arrivals: [HJArrival] = []
    var at = 20
    for id in 1...count {
        let length = rng.inRange(t.shipLengths)
        // A hull no berth in this harbour could ever take is not difficulty, it
        // is a broken level — the player would have no move at all.
        let draft = min(rng.inRange(t.draftRange), maxUsableDepth)
        let cargo = rng.pick(t.cargoes)
        let tons = 2 + rng.int(5)
        let vip = t.usesVIP && rng.int(6) == 0
        // Patience is stored doubled; these are ticks of real waiting.
        let patience = (vip ? 320 : 640) + rng.int(300)
        arrivals.append(HJArrival(tick: at,
                                  ship: HJShip(id: id, length: length, draft: draft,
                                               cargo: cargo, tons: tons,
                                               patienceTicks: patience * 2, isVIP: vip)))
        at += rng.inRange(t.arrivalGap)
    }
    return arrivals
}

/// Events are scheduled from the seed, never rolled during play: the harness has
/// to be able to replay a shift tick for tick.
func forgeEvents(template t: HJPortTemplate, harbor: HJHarborDef, span: Int,
                 rng: inout ForgeRNG) -> ([HJSlotOutage], [HJStormWindow]) {
    var outages: [HJSlotOutage] = []
    var storms: [HJStormWindow] = []
    if t.usesOutages {
        for _ in 0..<(1 + rng.int(2)) {
            let start = 100 + rng.int(max(1, span - 400))
            outages.append(HJSlotOutage(slot: rng.int(harbor.slots.count),
                                        startTick: start,
                                        endTick: start + 200 + rng.int(201)))
        }
    }
    if t.usesStorms {
        let start = 150 + rng.int(max(1, span - 700))
        storms.append(HJStormWindow(startTick: start, endTick: start + 600))
    }
    return (outages, storms)
}

/// `parTicks` and the star targets are left at zero here — they are calibrated
/// from policy S when the shift is accepted (see Gate.swift).
func forgeShift(port: Int, shift: Int, salt: Int) -> HJShiftDef {
    let t = HJCatalog.ports[port - 1]
    var rng = ForgeRNG(seed: forgeSeed(port: port, shift: shift, salt: salt))
    let harbor = forgeHarbor(template: t, rng: &rng)
    let arrivals = forgeArrivals(template: t, harbor: harbor, rng: &rng)
    let span = (arrivals.last?.tick ?? 500) + 600
    let (outages, storms) = forgeEvents(template: t, harbor: harbor, span: span, rng: &rng)
    return HJShiftDef(port: port, shift: shift, harbor: harbor, arrivals: arrivals,
                      outages: outages, storms: storms,
                      parTicks: 0, target2: 0, target3: 0)
}
