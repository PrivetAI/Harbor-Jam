import Foundation

/// Deterministic RNG for board construction. Named apart from the app's `HJRandom` so the
/// two can never be confused once the app's generator is deleted.
struct HJForgeRandom {
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
    mutating func pick<T>(_ a: [T]) -> T? { a.isEmpty ? nil : a[int(a.count)] }
}

/// FORWARD board construction.
///
/// The shipped generator built boards by undoing a solution: boats were placed in reverse
/// exit order with each corridor forced clear of every later-exiting boat, which
/// guaranteed a greedy exit order always existed and made four of the five mechanics
/// mathematically inert. Nothing here knows a solution. A board is just a legal
/// arrangement; whether it is solvable is decided by the search, and whether it is worth
/// shipping is decided by the acceptance gate.
enum HJForge {

    /// Every cell a hull would sweep on its way off the board, ignoring obstacles.
    static func exitCorridor(for boat: HJBoat, gridW: Int, gridH: Int) -> Set<HJCell> {
        var out = Set<HJCell>()
        var probe = boat
        var guardCount = 0
        while guardCount < gridW + gridH + 4 {
            guardCount += 1
            probe.x += boat.bow.dx
            probe.y += boat.bow.dy
            let inside = probe.cells.filter { $0.x >= 0 && $0.x < gridW && $0.y >= 0 && $0.y < gridH }
            if inside.isEmpty { break }
            out.formUnion(inside)
        }
        return out
    }

    /// True when following `anchoredBy` from `lock` ever reaches `key` — which would make
    /// the pair mutually un-exitable.
    private static func wouldCycle(boats: [HJBoat], lockID: Int, keyID: Int) -> Bool {
        var seen = Set<Int>()
        var cursor: Int? = keyID
        while let c = cursor, !seen.contains(c) {
            if c == lockID { return true }
            seen.insert(c)
            cursor = boats.first(where: { $0.id == c })?.anchoredBy
        }
        return false
    }

    static func board(seed: UInt64, config: HJLevelConfig) -> HJBoardState? {
        var rng = HJForgeRandom(seed: seed)
        let w = config.gridW, h = config.gridH

        // ---- hulls -----------------------------------------------------------------
        var boats: [HJBoat] = []
        var occupied = Set<HJCell>()
        var bargesLeft = config.bargeCount

        for id in 0..<config.boatCount {
            var placed = false
            for _ in 0..<240 {
                let isBarge = bargesLeft > 0 && rng.int(3) == 0
                let length = isBarge ? 2 : (rng.int(3) == 0 ? 3 : 2)
                guard let bow = rng.pick(HJDirection.allCases) else { break }
                var boat = HJBoat(id: id, x: 0, y: 0, length: length, isBarge: isBarge,
                                  bow: bow, hullIndex: rng.int(8), anchoredBy: nil,
                                  throttle: 1 + rng.int(3))
                let maxX = w - boat.width, maxY = h - boat.height
                guard maxX >= 0, maxY >= 0 else { continue }
                boat.x = rng.int(maxX + 1)
                boat.y = rng.int(maxY + 1)
                let footprint = Set(boat.cells)
                guard footprint.isDisjoint(with: occupied) else { continue }
                if isBarge { bargesLeft -= 1 }
                occupied.formUnion(footprint)
                boats.append(boat)
                placed = true
                break
            }
            if !placed { return nil }   // board too crowded for this envelope
        }

        // ---- buoy chains, with no ordering relationship whatsoever -------------------
        // The shipped generator always keyed a chain to a boat exiting EARLIER than its
        // lock, so ascending order satisfied all 94 of them for free. Here a chain is a
        // real constraint; only cycles are excluded.
        var chainsLeft = config.chainCount
        var attempts = 0
        while chainsLeft > 0 && attempts < 80 && boats.count >= 3 {
            attempts += 1
            let lockIdx = rng.int(boats.count)
            let keyIdx = rng.int(boats.count)
            if lockIdx == keyIdx { continue }
            if boats[lockIdx].anchoredBy != nil || boats[lockIdx].isBarge { continue }
            if wouldCycle(boats: boats, lockID: boats[lockIdx].id, keyID: boats[keyIdx].id) { continue }
            boats[lockIdx].anchoredBy = boats[keyIdx].id
            chainsLeft -= 1
        }

        // ---- sandbars, placed INSIDE the corridors ----------------------------------
        // Inverted polarity. They used to be drawn from the complement of every corridor,
        // which is precisely why the tide could never block anything.
        var corridorCells = Set<HJCell>()
        for b in boats { corridorCells.formUnion(exitCorridor(for: b, gridW: w, gridH: h)) }
        corridorCells.subtract(occupied)

        var sandbars: [HJCell] = []
        if config.useTide {
            let want = 2 + rng.int(3)
            let pool = corridorCells.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            guard pool.count >= 2 else { return nil }
            var chosen = Set<HJCell>()
            var tries = 0
            while chosen.count < min(want, pool.count) && tries < 120 {
                tries += 1
                chosen.insert(pool[rng.int(pool.count)])
            }
            sandbars = Array(chosen)
            // The board must actually be able to interfere with at least two hulls,
            // otherwise the tide is decoration again.
            let affected = boats.filter { b in
                !exitCorridor(for: b, gridW: w, gridH: h).isDisjoint(with: chosen)
            }
            if affected.count < 2 { return nil }
        }

        // ---- turning basins ---------------------------------------------------------
        var basins: [HJCell] = []
        if config.basinCount > 0 {
            var free = Set<HJCell>()
            for y in 0..<h { for x in 0..<w { free.insert(HJCell(x: x, y: y)) } }
            free.subtract(occupied)
            free.subtract(sandbars)
            let pool = free.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            guard pool.count >= config.basinCount else { return nil }
            var chosen = Set<HJCell>()
            var tries = 0
            while chosen.count < config.basinCount && tries < 120 {
                tries += 1
                chosen.insert(pool[rng.int(pool.count)])
            }
            guard chosen.count == config.basinCount else { return nil }
            basins = Array(chosen)
        }

        // ---- current lanes, now with a reversal period ------------------------------
        var currents: [HJCurrentLane] = []
        if config.useCurrents {
            let laneCount = 1 + rng.int(2)
            var tries = 0
            while currents.count < laneCount && tries < 40 {
                tries += 1
                let isRow = rng.bool()
                let index = isRow ? rng.int(h) : rng.int(w)
                if currents.contains(where: { $0.isRow == isRow && $0.index == index }) { continue }
                let push: HJDirection = isRow ? (rng.bool() ? .north : .south)
                                              : (rng.bool() ? .east : .west)
                currents.append(HJCurrentLane(isRow: isRow, index: index,
                                              push: push, period: 2 + rng.int(3)))
            }
            if currents.isEmpty { return nil }
        }

        // ---- ferry ------------------------------------------------------------------
        var ferry: HJFerry? = nil
        if config.useFerry {
            ferry = HJFerry(row: rng.int(h), x: rng.int(w), length: 2, stride: 1 + rng.int(2))
        }

        let state = HJBoardState(gridW: w, gridH: h, boats: boats, exitedIDs: [],
                                 sandbars: sandbars, currents: currents, ferry: ferry,
                                 tideEnabled: config.useTide, tideHigh: true,
                                 basins: basins, taps: 0, night: config.night)

        // A board whose ferry starts on top of a hull is malformed, not merely hard.
        if !state.ferryCells().isDisjoint(with: occupied) { return nil }
        return state
    }
}

/// Structural checks on the forward generator. These assert PROPERTIES, never counts —
/// the yield of a generator being written for the first time is not knowable in advance.
func forgeRunForgeChecks() -> Int {
    var failures = 0
    func expect(_ ok: Bool, _ what: String) {
        print(ok ? "PASS  \(what)" : "FAIL  \(what)")
        if !ok { failures += 1 }
    }

    var produced = 0
    var problems: [String] = []

    for chapter in 0..<HJCatalog.chapters.count {
        for level in stride(from: 0, to: HJCatalog.levelsPerChapter, by: 4) {
            let config = HJCatalog.config(chapter: chapter, level: level)
            for salt in 0..<40 {
                let seed = HJCatalog.seed(chapter: chapter, level: level) &+ UInt64(salt) &* 0x2545F4914F6CDD1D
                guard let b = HJForge.board(seed: seed, config: config) else { continue }
                produced += 1
                let tag = "\(chapter)-\(level)+\(salt)"

                var seen = Set<HJCell>()
                for boat in b.boats {
                    for c in boat.cells {
                        if !b.inBounds(c) { problems.append("\(tag): hull out of bounds") }
                        if seen.contains(c) { problems.append("\(tag): hulls overlap") }
                        seen.insert(c)
                    }
                    if boat.throttle < 1 || boat.throttle > 3 { problems.append("\(tag): throttle \(boat.throttle)") }
                }
                if b.boats.count != config.boatCount { problems.append("\(tag): boat count") }
                if !Set(b.sandbars).isDisjoint(with: seen) { problems.append("\(tag): sandbar under a hull") }
                if !Set(b.basins).isDisjoint(with: Set(b.sandbars)) { problems.append("\(tag): basin on a sandbar") }
                if b.basins.count != config.basinCount { problems.append("\(tag): basin count") }
                let chains = b.boats.filter { $0.anchoredBy != nil }.count
                if chains != config.chainCount { problems.append("\(tag): chain count \(chains)") }
                for lane in b.currents where lane.period < 2 || lane.period > 4 {
                    problems.append("\(tag): lane period \(lane.period)")
                }
                if config.useTide && b.sandbars.count < 2 { problems.append("\(tag): tide board without bars") }
            }
        }
    }

    print("boards produced across every chapter envelope: \(produced)")
    expect(produced > 0, "the forward generator produces boards at all")
    expect(problems.isEmpty, "every produced board is structurally legal")
    for p in problems.prefix(8) { print("        \(p)") }

    if failures == 0 { print("FORGE OK"); return 0 }
    print("FORGE FAILED — \(failures) assertion(s)")
    return 1
}
