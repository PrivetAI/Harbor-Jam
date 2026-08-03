import Foundation

/// Every balance number in the game. The tuning loop that has to satisfy the
/// acceptance gate edits this enum and `HJCatalog.ports`, and nothing else — a
/// magic number anywhere else in the codebase is a bug, because it would be a
/// lever the gate cannot see.
enum HJTuning {
    /// The ONLY place ticks map to wall-clock time. Every balance number in the
    /// game, the whole baked corpus and every policy in the harness are in ticks,
    /// so changing this re-paces the game for a human without moving a single
    /// measured property — the acceptance gate never looks at seconds.
    ///
    /// It was 20. Play-testing on device showed the obvious calibration gap: the
    /// reference policy acts on the tick a ship arrives, a person needs a couple
    /// of seconds to read the hull and pick a berth. At 20 Hz a shift lost two
    /// ships in the first twenty seconds. At 10 Hz patience runs 64–94 s and
    /// ships arrive every 13–19 s, which is a mobile pace.
    static let tickHz = 10

    /// Work units per ton, in doubled units (see `HJShip.unloadLeft`), so a hull
    /// of `tons` occupies her berths for `tons · workPerTon` ticks on matching
    /// gear and 2.5× that on the wrong gear.
    ///
    /// These are large relative to `channelTransitTicks` on purpose. The channel
    /// is a serial resource: every ship spends 2·transit in it, so transit sets a
    /// hard ceiling on throughput. Unloading is parallel across berths, so it is
    /// what fills the quay. Measured with a short unload and a long channel, the
    /// quay sat nearly empty and the arrival queue exploded — packing, gear and
    /// tide could not matter, and all three policies failed identically.
    static func workPerTon(_ cargo: HJCargo) -> Int {
        switch cargo {
        case .container: return 60
        case .bulk: return 75
        case .liquid: return 50
        }
    }

    /// Coins per ton.
    static func rate(_ cargo: HJCargo) -> Int {
        switch cargo {
        case .container: return 10
        case .bulk: return 8
        case .liquid: return 12
        }
    }

    static let vipRateMultiplier = 3
    static let speedRate = 1            // score per tick saved against par
    /// Par is set this far above the reference policy's own finishing time.
    /// At 100 the reference policy's speed bonus would be exactly zero, which
    /// makes the whole speed term unreachable for a player of that standard.
    static let parCushionPercent = 115
    static let baseReputation = 3
    static let target3Percent = 92      // of policy S's score
    static let target2Percent = 70

    static let unloadDiscountPerCraneLevel = 8    // percent
    static let transitDiscountPerTugLevel = 10    // percent
    static let longShipLength = 4                 // transit ×1.5 in ports that penalise it
    static let patiencePerTick = 2
    static let patiencePerTickInStorm = 3
}

struct HJPortTemplate {
    var index: Int              // 1...7
    var name: String
    var tagline: String
    var slotCount: Int
    var depthRange: ClosedRange<Int>
    var equipment: [HJEquipment]     // pool drawn from when laying out a quay
    var cargoes: [HJCargo]
    /// Ticks between arrivals. This is the primary difficulty dial: mean gap
    /// against mean berth occupancy decides how full the quay runs, and mean gap
    /// against 2·channelTransitTicks decides whether the channel can keep up at
    /// all. A gap below 2·transit means the queue grows without bound and every
    /// policy loses — that is an unplayable shift, not a hard one.
    var arrivalGap: ClosedRange<Int>
    var channelTransitTicks: Int
    var tideAmplitude: Int
    var tideStepTicks: Int
    var shipLengths: ClosedRange<Int>
    var draftRange: ClosedRange<Int>
    var shipCount: ClosedRange<Int>
    var usesOutages: Bool
    var usesStorms: Bool
    var usesVIP: Bool
    var longShipTransitPenalty: Bool
}

enum HJCatalog {
    static let shiftsPerPort = 12
    static var portCount: Int { ports.count }
    static var totalShifts: Int { portCount * shiftsPerPort }

    /// Port `n` opens at 20·(n−1) stars, out of 36 available per port.
    static func starsToUnlock(port: Int) -> Int { max(0, 20 * (port - 1)) }

    static func template(port: Int) -> HJPortTemplate? {
        ports.first { $0.index == port }
    }

    /// Each port introduces exactly one new thing and nothing else. The order is
    /// the teaching order: a mechanic the player has not met cannot be what
    /// beats them.
    static let ports: [HJPortTemplate] = [
        HJPortTemplate(index: 1, name: "Quiet Cove", tagline: "Learn the quay",
                       slotCount: 8, depthRange: 5...5, equipment: [.crane],
                       cargoes: [.container], arrivalGap: 130...190,
                       channelTransitTicks: 20,
                       tideAmplitude: 0, tideStepTicks: 0,
                       shipLengths: 2...3, draftRange: 1...3, shipCount: 12...16,
                       usesOutages: false, usesStorms: false, usesVIP: false,
                       longShipTransitPenalty: false),
        HJPortTemplate(index: 2, name: "Tidewater Quay", tagline: "Mind the water line",
                       slotCount: 9, depthRange: 2...5, equipment: [.crane],
                       cargoes: [.container], arrivalGap: 120...180,
                       channelTransitTicks: 20,
                       tideAmplitude: 1, tideStepTicks: 120,
                       shipLengths: 2...4, draftRange: 1...4, shipCount: 14...18,
                       usesOutages: false, usesStorms: false, usesVIP: false,
                       longShipTransitPenalty: false),
        HJPortTemplate(index: 3, name: "Narrow Channel", tagline: "One way in",
                       slotCount: 9, depthRange: 2...5, equipment: [.crane],
                       cargoes: [.container], arrivalGap: 110...165,
                       channelTransitTicks: 40,
                       tideAmplitude: 1, tideStepTicks: 120,
                       shipLengths: 2...4, draftRange: 1...4, shipCount: 16...20,
                       usesOutages: false, usesStorms: false, usesVIP: false,
                       longShipTransitPenalty: false),
        HJPortTemplate(index: 4, name: "Mixed Berths", tagline: "Right gear, right berth",
                       slotCount: 10, depthRange: 2...5,
                       equipment: [.crane, .conveyor, .pipeline],
                       cargoes: [.container, .bulk, .liquid], arrivalGap: 105...160,
                       channelTransitTicks: 40,
                       tideAmplitude: 1, tideStepTicks: 120,
                       shipLengths: 2...4, draftRange: 1...4, shipCount: 16...22,
                       usesOutages: false, usesStorms: false, usesVIP: false,
                       longShipTransitPenalty: false),
        HJPortTemplate(index: 5, name: "Storm Roads", tagline: "Weather and repairs",
                       slotCount: 10, depthRange: 2...5,
                       equipment: [.crane, .conveyor, .pipeline],
                       cargoes: [.container, .bulk, .liquid], arrivalGap: 110...165,
                       channelTransitTicks: 40,
                       tideAmplitude: 1, tideStepTicks: 120,
                       shipLengths: 2...4, draftRange: 1...4, shipCount: 18...24,
                       usesOutages: true, usesStorms: true, usesVIP: false,
                       longShipTransitPenalty: false),
        HJPortTemplate(index: 6, name: "Deepwater Port", tagline: "Big hulls, deep water",
                       slotCount: 12, depthRange: 3...7,
                       equipment: [.crane, .conveyor, .pipeline],
                       // Longer hulls than any other port: a mean length of 4 on
                       // a 12-berth quay means only three ships fit at once, so
                       // this port needs a slacker arrival stream than port 7
                       // despite looking smaller on paper.
                       cargoes: [.container, .bulk, .liquid], arrivalGap: 135...195,
                       channelTransitTicks: 40,
                       tideAmplitude: 2, tideStepTicks: 110,
                       shipLengths: 3...5, draftRange: 2...5, shipCount: 18...23,
                       usesOutages: true, usesStorms: true, usesVIP: false,
                       longShipTransitPenalty: true),
        HJPortTemplate(index: 7, name: "Grand Harbor", tagline: "Everything at once",
                       slotCount: 12, depthRange: 3...7,
                       equipment: [.crane, .conveyor, .pipeline, .none],
                       cargoes: [.container, .bulk, .liquid], arrivalGap: 115...170,
                       channelTransitTicks: 40,
                       tideAmplitude: 2, tideStepTicks: 110,
                       shipLengths: 2...5, draftRange: 1...5, shipCount: 22...28,
                       usesOutages: true, usesStorms: true, usesVIP: true,
                       longShipTransitPenalty: true),
    ]
}

// MARK: - The baked corpus

extension HJCatalog {
    private static var shiftCache: [HJShiftDef]? = nil

    /// The 84 shifts accepted by the offline gate. Generation does not happen on
    /// the device: a shift is only in this file because greedy play measurably
    /// lost ground on it, and that decision needs the whole policy harness.
    static func loadShifts() -> [HJShiftDef] {
        if let c = shiftCache { return c }
        guard let url = Bundle.main.url(forResource: "shifts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([HJShiftDef].self, from: data)
        else {
            shiftCache = []
            return []
        }
        shiftCache = decoded
        return decoded
    }

    static func shift(port: Int, shift: Int) -> HJShiftDef? {
        loadShifts().first { $0.port == port && $0.shift == shift }
    }
}

// MARK: - Watch (endless)

enum HJWatch {
    static let slotCount = 10
    static let waveTicks = 900          // 90 s at 10 Hz — one upgrade choice per wave
    static let shipsPerWave = 6
    /// Arrival spacing shrinks 4 % per wave and floors at 40 % of the opening
    /// gap. Without a floor the stream eventually outruns the channel itself and
    /// the run ends on arithmetic rather than on a mistake.
    static let openingGap = 150
    static let gapDecayPercent = 96
    static let minGapPercent = 40

    /// A deterministic endless shift. Uses the same `HJShiftDef` type as the
    /// campaign, so `HJSim` does not know the difference and neither does the
    /// harness. `parTicks` and both targets are `Int.max`: the Watch scores in
    /// tons, never in stars.
    static func shift(seed: UInt64, waves: Int) -> HJShiftDef {
        var rng = HJWatchRNG(seed: seed)
        var slots: [HJSlot] = []
        let gear: [HJEquipment] = [.crane, .conveyor, .pipeline]
        for i in 0..<slotCount {
            slots.append(HJSlot(depth: 3 + rng.int(4), equipment: gear[i % gear.count]))
        }
        for i in stride(from: slots.count - 1, to: 0, by: -1) {
            slots.swapAt(i, rng.int(i + 1))
        }

        var arrivals: [HJArrival] = []
        var at = 30
        var gap = openingGap
        let floor = openingGap * minGapPercent / 100
        var id = 1
        for _ in 0..<waves {
            for _ in 0..<shipsPerWave {
                let length = 2 + rng.int(4)
                let draft = 1 + rng.int(5)
                let cargo = HJCargo.allCases[rng.int(3)]
                arrivals.append(HJArrival(tick: at,
                                          ship: HJShip(id: id, length: length,
                                                       draft: min(draft, 6),
                                                       cargo: cargo,
                                                       tons: 2 + rng.int(5),
                                                       patienceTicks: (620 + rng.int(300)) * 2,
                                                       isVIP: false)))
                id += 1
                at += gap - rng.int(30)
            }
            gap = max(floor, gap * gapDecayPercent / 100)
        }

        return HJShiftDef(port: 0, shift: 0,
                          harbor: HJHarborDef(slots: slots, channelTransitTicks: 30,
                                              tideAmplitude: 1, tideStepTicks: 130,
                                              roadsteadCapacity: 5),
                          arrivals: arrivals, outages: [], storms: [],
                          parTicks: Int.max, target2: Int.max, target3: Int.max)
    }
}

/// SplitMix64 again — the harness has its own copy, and the app must not depend
/// on the tooling.
struct HJWatchRNG {
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
}
