import Foundation

/// Deterministic SplitMix64 RNG — identical sequences across launches for a given seed.
struct HJRandom {
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
        guard upper > 0 else { return 0 }
        return Int(next() % UInt64(upper))
    }
    mutating func bool() -> Bool { next() % 2 == 0 }
    mutating func pick<T>(_ array: [T]) -> T? {
        guard !array.isEmpty else { return nil }
        return array[int(array.count)]
    }
}

struct HJGeneratedLevel {
    var start: HJBoardState
    var par: Int                 // optimal taps = boat count (one tap exits exactly one boat)
    var solutionOrder: [Int]     // boat ids in exit order (the verified canonical solution)
}

enum HJGenerator {

    /// Generate a verified level. Tries successive salts until the canonical solution
    /// replays cleanly through the real engine — never returns an unverified board.
    static func level(seed: UInt64, config: HJLevelConfig, maxSalts: Int = 120) -> HJGeneratedLevel? {
        for salt in 0..<maxSalts {
            var rng = HJRandom(seed: seed &+ UInt64(salt) &* 0x2545F4914F6CDD1D)
            if let candidate = construct(rng: &rng, config: config),
               let verified = verify(candidate) {
                return verified
            }
        }
        return nil
    }

    /// Chapter/level accessor with in-memory cache.
    private static var cache: [String: HJGeneratedLevel] = [:]
    static func campaignLevel(chapter: Int, level: Int) -> HJGeneratedLevel? {
        let key = "\(chapter)-\(level)"
        if let hit = cache[key] { return hit }
        let generated = self.level(seed: HJCatalog.seed(chapter: chapter, level: level),
                                   config: HJCatalog.config(chapter: chapter, level: level))
        if let g = generated { cache[key] = g }
        return generated
    }

    static func dailyLevel(dayKey: Int) -> HJGeneratedLevel? {
        let seed = UInt64(bitPattern: Int64(dayKey)) &* 0x9E3779B97F4A7C15 &+ 0xDA11
        if let live = level(seed: seed, config: HJCatalog.dailyConfig, maxSalts: 60) {
            return live
        }
        // Fallback to the pre-verified pool — deterministic pick by day.
        let poolSeed = HJCatalog.dailyFallbackSeeds[abs(dayKey) % HJCatalog.dailyFallbackSeeds.count]
        return level(seed: poolSeed, config: HJCatalog.dailyConfig, maxSalts: 200)
    }

    // MARK: - Reverse construction

    /// Build boats in REVERSE exit order: when boat i is placed, only later-exiting boats
    /// exist, and i's straight corridor to the edge must be clear of them. Earlier-exiting
    /// boats placed afterwards may sit inside that corridor — they exit first, so the
    /// canonical order (0,1,2,…) always works. Solvable by construction.
    private static func construct(rng: inout HJRandom, config: HJLevelConfig) -> HJGeneratedLevel? {
        let w = config.gridW, h = config.gridH
        var boats: [HJBoat] = []          // will hold ids N-1 … 0 in placement order
        var corridors: [Int: Set<HJCell>] = [:]   // boat id -> exit corridor cells

        let total = config.boatCount
        var bargesLeft = config.bargeCount

        for exitIndex in stride(from: total - 1, through: 0, by: -1) {
            let occupiedNow = Set(boats.flatMap { $0.cells })
            var placed = false
            for _ in 0..<160 {
                let isBarge = bargesLeft > 0 && rng.int(3) == 0
                let length = isBarge ? 2 : (rng.int(3) == 0 ? 3 : 2)
                guard let bow = rng.pick(HJDirection.allCases) else { break }
                var boat = HJBoat(id: exitIndex, x: 0, y: 0, length: length, isBarge: isBarge,
                                  bow: bow, hullIndex: rng.int(8), anchoredBy: nil)
                let maxX = w - boat.width, maxY = h - boat.height
                guard maxX >= 0, maxY >= 0 else { continue }
                boat.x = rng.int(maxX + 1)
                boat.y = rng.int(maxY + 1)
                let footprint = Set(boat.cells)
                guard footprint.isDisjoint(with: occupiedNow) else { continue }
                let corridor = exitCorridor(for: boat, gridW: w, gridH: h)
                guard corridor.isDisjoint(with: occupiedNow) else { continue }
                if isBarge { bargesLeft -= 1 }
                boats.append(boat)
                corridors[boat.id] = corridor.union(footprint)
                placed = true
                break
            }
            if !placed { return nil }
        }

        boats.sort { $0.id < $1.id }

        // Buoy anchor chains: later-exiting boat anchored by an earlier-exiting one.
        var chainsLeft = config.chainCount
        var chainAttempts = 0
        while chainsLeft > 0 && chainAttempts < 40 && total >= 4 {
            chainAttempts += 1
            let keyIdx = rng.int(total - 2)              // exits earlier
            let lockIdx = keyIdx + 1 + rng.int(total - keyIdx - 1)  // exits later
            if boats[lockIdx].anchoredBy == nil && !boats[lockIdx].isBarge {
                boats[lockIdx].anchoredBy = boats[keyIdx].id
                chainsLeft -= 1
            }
        }

        // Protected cells: every boat footprint + every exit corridor.
        var protected = Set<HJCell>()
        for (_, cells) in corridors { protected.formUnion(cells) }

        // Sandbars (solid at low tide) — never inside any corridor, so the canonical
        // solution is tide-proof by construction.
        var sandbars: [HJCell] = []
        if config.useTide {
            let want = 2 + rng.int(3)
            var tries = 0
            while sandbars.count < want && tries < 80 {
                tries += 1
                let c = HJCell(x: rng.int(w), y: rng.int(h))
                if !protected.contains(c) && !sandbars.contains(c) {
                    sandbars.append(c)
                }
            }
            if sandbars.count < 2 { return nil }   // tide chapter must actually show tides
        }

        // Current lanes — they only push boats that END a slide inside the lane; the
        // canonical solution only ever exits boats, so lanes never break it.
        var currents: [HJCurrentLane] = []
        if config.useCurrents {
            let laneCount = 1 + rng.int(2)
            var guard0 = 0
            while currents.count < laneCount && guard0 < 30 {
                guard0 += 1
                let isRow = rng.bool()
                let index = isRow ? rng.int(h) : rng.int(w)
                if currents.contains(where: { $0.isRow == isRow && $0.index == index }) { continue }
                let push: HJDirection = isRow ? (rng.bool() ? .north : .south)
                                              : (rng.bool() ? .east : .west)
                currents.append(HJCurrentLane(isRow: isRow, index: index, push: push))
            }
        }

        var ferry: HJFerry? = nil
        if config.useFerry {
            // Prefer a row with few sandbar collisions; replay verification is the referee.
            let row = rng.int(h)
            ferry = HJFerry(row: row, x: rng.int(w), length: 2, stride: 1 + rng.int(2))
        }

        let state = HJBoardState(gridW: w, gridH: h, boats: boats, exitedIDs: [],
                                 sandbars: sandbars, currents: currents, ferry: ferry,
                                 tideEnabled: config.useTide, tideHigh: true,
                                 tugTokens: config.tugTokens, taps: 0, night: config.night)
        return HJGeneratedLevel(start: state, par: total, solutionOrder: Array(0..<total))
    }

    private static func exitCorridor(for boat: HJBoat, gridW: Int, gridH: Int) -> Set<HJCell> {
        var out = Set<HJCell>()
        var probe = boat
        while true {
            probe.x += boat.bow.dx
            probe.y += boat.bow.dy
            let inside = probe.cells.filter { $0.x >= 0 && $0.x < gridW && $0.y >= 0 && $0.y < gridH }
            if inside.isEmpty { break }
            out.formUnion(inside)
            if out.count > gridW * gridH { break }
        }
        return out
    }

    // MARK: - Verification (real-engine replay)

    /// Replays the canonical solution through the actual engine. Requires every tap to
    /// exit its boat, the board to end cleared, and the start to be a genuine puzzle
    /// (some boats initially blocked). Returns nil on any deviation.
    private static func verify(_ level: HJGeneratedLevel) -> HJGeneratedLevel? {
        var state = level.start
        guard !state.isCleared else { return nil }

        for id in level.solutionOrder {
            let outcome = HJEngine.tap(boatID: id, state: &state)
            guard case .exited(let exitedID) = outcome, exitedID == id else { return nil }
        }
        guard state.isCleared, state.taps == level.par else { return nil }

        // Reject trivial boards: enough boats must be unable to exit on the very first tap.
        let n = level.start.boats.count
        if n >= 5 {
            var blockedAtStart = 0
            for boat in level.start.boats {
                var probe = level.start
                let outcome = HJEngine.tap(boatID: boat.id, state: &probe)
                if case .exited = outcome {} else { blockedAtStart += 1 }
            }
            let needed = max(1, n / 4)
            guard blockedAtStart >= needed else { return nil }
        }
        return level
    }
}
