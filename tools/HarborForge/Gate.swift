import Foundation

struct HJGateResult {
    var accepted: Bool
    var rejectionClause: String?
    var greedyRatio: Double        // median careless line / witness length; .infinity if careless fails
    var witness: [Int]
}

/// The acceptance gate. A board ships only if a careless player measurably does worse
/// than a thoughtful one, and only if every mechanic on it changes the answer.
///
/// Acceptance is deliberately NOT defined against "greedy fails to reach the optimum".
/// A capped search that silently returns a non-minimum would make that condition
/// trivially true on every board — the same trap that turned the old verifier into a
/// difficulty-REMOVAL filter. Clause (b) is stated as a ratio so it does not become
/// easier to satisfy as par grows.
enum HJGate {

    static let rolloutCount = 200
    static let greedyRatioFloor = 1.25

    /// Median careless line length as a multiple of the witness. `.infinity` when the
    /// careless player more often than not fails to clear the board at all.
    static func greedyRatio(start: HJBoardState, witnessLength: Int, seed: UInt64) -> Double {
        var rng = ForgeRNG(seed: seed)
        var lengths: [Double] = []
        for _ in 0..<rolloutCount {
            let r = forgeRolloutB(start: start, rng: &rng)
            lengths.append(r.cleared ? Double(r.moves) : Double.infinity)
        }
        lengths.sort()
        let median = lengths[lengths.count / 2]
        guard median.isFinite else { return .infinity }
        return median / Double(max(witnessLength, 1))
    }

    /// Can a careless player reach a state where nothing they press ever helps?
    static func reachesDeadEnd(start: HJBoardState, seed: UInt64) -> Bool {
        var rng = ForgeRNG(seed: seed &+ 7)
        for _ in 0..<rolloutCount {
            if forgeRolloutB(start: start, rng: &rng).deadlocked { return true }
        }
        return false
    }

    /// Rebuild the board with one mechanic removed, for clause (d).
    private static func without(_ mechanic: String, _ s: HJBoardState) -> HJBoardState {
        var out = s
        switch mechanic {
        case "sandbars": out.sandbars = []; out.tideEnabled = false
        case "currents": out.currents = []
        case "ferry":    out.ferry = nil
        case "basins":   out.basins = []
        case "chains":   for i in out.boats.indices { out.boats[i].anchoredBy = nil }
        default: break
        }
        return out
    }

    private static func presentMechanics(_ s: HJBoardState) -> [String] {
        var out: [String] = []
        if s.tideEnabled && !s.sandbars.isEmpty { out.append("sandbars") }
        if !s.currents.isEmpty { out.append("currents") }
        if s.ferry != nil { out.append("ferry") }
        if !s.basins.isEmpty { out.append("basins") }
        if s.boats.contains(where: { $0.anchoredBy != nil }) { out.append("chains") }
        return out
    }

    /// Clauses are ordered cheapest-first so an expensive re-search only happens on a
    /// board that has already earned it.
    static func accept(start: HJBoardState, seed: UInt64, checkMechanics: Bool = true) -> HJGateResult {
        guard let witness = HJSearch.witness(from: start) else {
            return HJGateResult(accepted: false, rejectionClause: "unsolvable", greedyRatio: 0, witness: [])
        }

        // (a) the line must need more taps than there are boats — i.e. some hull is moved
        //     more than once. This is the move class the old game structurally excluded.
        if witness.count <= start.boats.count {
            return HJGateResult(accepted: false, rejectionClause: "a: par <= boats", greedyRatio: 0, witness: witness)
        }

        // (c) at least two hulls appear three or more times, so the board is not one long
        //     shuffle of a single boat with everyone else leaving on cue.
        var counts: [Int: Int] = [:]
        for id in witness { counts[id, default: 0] += 1 }
        if counts.values.filter({ $0 >= 3 }).count < 2 {
            return HJGateResult(accepted: false, rejectionClause: "c: fewer than 2 hulls moved 3+ times",
                                greedyRatio: 0, witness: witness)
        }

        // No shipped board may be reachable into a dead end.
        if reachesDeadEnd(start: start, seed: seed) {
            return HJGateResult(accepted: false, rejectionClause: "dead end reachable", greedyRatio: 0, witness: witness)
        }

        // (b) careless play must measurably cost.
        let ratio = greedyRatio(start: start, witnessLength: witness.count, seed: seed)
        if ratio < greedyRatioFloor {
            return HJGateResult(accepted: false, rejectionClause: "b: greedy ratio \(String(format: "%.2f", ratio))",
                                greedyRatio: ratio, witness: witness)
        }

        // (d) every mechanic on the board must change the answer. This is the test the old
        //     verifier inverted: it re-rolled any seed where a mechanic would have mattered.
        if checkMechanics {
            for m in presentMechanics(start) {
                let stripped = without(m, start)
                let alt = HJSearch.witness(from: stripped)
                if let alt = alt, alt.count == witness.count {
                    return HJGateResult(accepted: false, rejectionClause: "d: \(m) is inert",
                                        greedyRatio: ratio, witness: witness)
                }
            }
        }

        return HJGateResult(accepted: true, rejectionClause: nil, greedyRatio: ratio, witness: witness)
    }
}

// MARK: - Baked table

struct HJLevelRecordOut: Codable {
    var par: Int
    var witness: [Int]
    var start: HJBoardState
}

struct HJLevelTableFileOut: Codable {
    var version: Int
    var campaign: [String: HJLevelRecordOut]
    var daily: [HJLevelRecordOut]
}

/// Search salts for one envelope until a board passes every clause.
func forgeBakeOne(chapter: Int, level: Int, maxSalts: Int, tally: inout [String: Int]) -> HJLevelRecordOut? {
    let config = HJCatalog.config(chapter: chapter, level: level)
    for salt in 0..<maxSalts {
        let seed = HJCatalog.seed(chapter: chapter, level: level) &+ UInt64(salt) &* 0x2545F4914F6CDD1D
        guard let board = HJForge.board(seed: seed, config: config) else {
            tally["malformed", default: 0] += 1
            continue
        }
        let verdict = HJGate.accept(start: board, seed: seed)
        if verdict.accepted {
            return HJLevelRecordOut(par: verdict.witness.count, witness: verdict.witness, start: board)
        }
        tally[verdict.rejectionClause ?? "unknown", default: 0] += 1
    }
    return nil
}

/// THE CHECKPOINT. Measures acceptance yield and, crucially, the zero-thought three-star
/// rate on boards that PASSED the gate — the one number nobody had measured. If that rate
/// is not below 15 %, work stops here and the parameters are retuned before another line
/// of app code is written.
func forgeRunYieldProbe(saltsPerLevel: Int) -> Int {
    let probes: [(Int, Int)] = [(0, 4), (1, 8), (2, 10), (3, 12), (4, 10), (5, 14), (6, 16)]
    var tally: [String: Int] = [:]
    var accepted: [(String, HJLevelRecordOut)] = []
    let started = ProcessInfo.processInfo.systemUptime

    for (chapter, level) in probes {
        if let rec = forgeBakeOne(chapter: chapter, level: level, maxSalts: saltsPerLevel, tally: &tally) {
            accepted.append(("\(chapter)-\(level)", rec))
        }
    }
    let elapsed = ProcessInfo.processInfo.systemUptime - started

    print("=== YIELD PROBE — \(probes.count) envelopes, up to \(saltsPerLevel) salts each ===")
    print("accepted            : \(accepted.count)/\(probes.count)")
    print("wall clock          : \(String(format: "%.1f", elapsed)) s")
    print("rejections by clause:")
    for (k, v) in tally.sorted(by: { $0.value > $1.value }) { print("   \(v)\t\(k)") }

    guard !accepted.isEmpty else {
        print("")
        print("STOP — nothing passed the gate. Retune before writing any more app code.")
        return 1
    }

    // The measurement the whole redesign exists to move.
    var runs = 0, threeStar = 0
    var parOverBoats: [Double] = []
    for (tag, rec) in accepted {
        var rng = ForgeRNG(seed: 99)
        for _ in 0..<500 {
            let r = forgeRolloutA(start: rec.start, rng: &rng)
            runs += 1
            if r.cleared && r.moves <= rec.par { threeStar += 1 }
        }
        parOverBoats.append(Double(rec.par) / Double(rec.start.boats.count))
        print("   \(tag): boats \(rec.start.boats.count), par \(rec.par)")
    }
    let rate = Double(threeStar) / Double(max(runs, 1)) * 100
    parOverBoats.sort()
    let medianRatio = parOverBoats[parOverBoats.count / 2]

    print("")
    print("zero-thought three-star rate on ACCEPTED boards : \(String(format: "%.2f", rate)) %   (was 96.63 %, ship gate < 15 %)")
    print("median par / boat count                        : \(String(format: "%.2f", medianRatio))   (was 1.00, ship gate >= 1.60)")

    if rate < 15.0 {
        print("")
        print("CHECKPOINT PASSED — the gate produces boards a careless player cannot three-star.")
        return 0
    }
    print("")
    print("CHECKPOINT FAILED — retune in this order, one lever at a time:")
    print("  1. bias the throttle draw toward 1 and 3 in HJForge.board")
    print("  2. raise basinCount in HJCatalog.config")
    print("  3. raise HJGate.greedyRatioFloor above 1.25")
    print("  4. lower boatCount in HJCatalog.config")
    return 1
}
