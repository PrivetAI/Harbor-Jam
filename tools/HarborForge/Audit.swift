import Foundation

/// Rollouts of each policy, per level.
let forgeRolloutsPerLevel = 500

struct ForgeLevelStat {
    var chapter: Int
    var level: Int
    var generated: Bool = false
    var boats: Int = 0
    var par: Int = 0
    var openingExits: Int = 0
    var openingNoops: Int = 0
    var policyARuns: Int = 0
    var policyAParRuns: Int = 0
    var deadlockRuns: Int = 0
}

/// Measure the shipped corpus and assert the known baseline. Returns a process exit code.
func forgeRunAudit() -> Int {
    var stats: [ForgeLevelStat] = []
    var ungenerated: [String] = []

    for chapter in 0..<HJCatalog.chapters.count {
        for level in 0..<HJCatalog.levelsPerChapter {
            var s = ForgeLevelStat(chapter: chapter, level: level)
            guard let g = HJGenerator.campaignLevel(chapter: chapter, level: level) else {
                ungenerated.append("\(chapter)-\(level)")
                stats.append(s)
                continue
            }
            s.generated = true
            s.boats = g.start.boats.count
            s.par = g.par

            let opts = forgeOptions(g.start)
            s.openingExits = opts.exits.count
            s.openingNoops = g.start.boats.filter { forgeTapIsInert(boatID: $0.id, state: g.start) }.count

            // Deterministic per-level seed so a rerun reproduces the same numbers.
            var rng = ForgeRNG(seed: UInt64(chapter &* 1_000 &+ level) &* 0x9E3779B97F4A7C15 &+ 0xF0
            )
            for _ in 0..<forgeRolloutsPerLevel {
                let a = forgeRolloutA(start: g.start, rng: &rng)
                s.policyARuns += 1
                if a.cleared && a.moves <= g.par { s.policyAParRuns += 1 }

                let b = forgeRolloutB(start: g.start, rng: &rng)
                if b.deadlocked { s.deadlockRuns += 1 }
            }
            stats.append(s)
        }
    }

    let gen = stats.filter { $0.generated }
    let totalBoats = gen.reduce(0) { $0 + $1.boats }
    let parEqBoats = gen.filter { $0.par == $0.boats }.count
    let runs = gen.reduce(0) { $0 + $1.policyARuns }
    let parRuns = gen.reduce(0) { $0 + $1.policyAParRuns }
    let openingExits = gen.reduce(0) { $0 + $1.openingExits }
    let openingNoops = gen.reduce(0) { $0 + $1.openingNoops }
    let deadLevels = gen.filter { $0.deadlockRuns > 0 }

    let greedyRate = Double(parRuns) / Double(max(runs, 1)) * 100
    let firstTapRate = Double(openingExits) / Double(max(totalBoats, 1)) * 100
    let inertRate = Double(openingNoops) / Double(max(totalBoats, 1)) * 100

    func pct(_ v: Double) -> String { String(format: "%.2f", v) }

    print("=== HARBOR JAM — CORPUS AUDIT (real engine, real generator) ===")
    print("levels generated                : \(gen.count)/\(HJCatalog.totalLevels)")
    if !ungenerated.isEmpty {
        print("FAILED TO GENERATE              : \(ungenerated.joined(separator: ", "))")
    }
    print("total boats in corpus           : \(totalBoats)")
    print("levels where par == boat count  : \(parEqBoats)/\(gen.count)")
    print("")
    print("policy A runs                   : \(runs)")
    print("policy A cleared at/under par   : \(parRuns)  (\(pct(greedyRate)) %)")
    print("boats exiting on the first tap  : \(openingExits)/\(totalBoats)  (\(pct(firstTapRate)) %)")
    print("opening taps that do nothing    : \(openingNoops)/\(totalBoats)  (\(pct(inertRate)) %)")
    print("levels reachable into a dead end: \(deadLevels.count)/\(gen.count)")
    for d in deadLevels.sorted(by: { ($0.chapter, $0.level) < ($1.chapter, $1.level) }) {
        let rate = Double(d.deadlockRuns) / Double(forgeRolloutsPerLevel) * 100
        print("   \(d.chapter)-\(d.level)  boats=\(d.boats)  dead in \(pct(rate)) % of rollouts")
    }

    // ---- Baseline assertions. These describe the game AS IT IS TODAY. They exist so a
    // regression in the harness itself is caught loudly; the redesign is expected to
    // break them deliberately, at which point they are replaced by the shipped gates.
    var failures: [String] = []
    func expect(_ ok: Bool, _ message: String) {
        print(ok ? "PASS  \(message)" : "FAIL  \(message)")
        if !ok { failures.append(message) }
    }

    print("")
    print("--- assertions ---")
    expect(gen.count == HJCatalog.totalLevels, "all \(HJCatalog.totalLevels) levels generate")
    expect(openingNoops == 0, "no tap is free — every tap ticks the world")
    // The LEGACY reverse-construction corpus is scheduled for deletion; live currents can
    // push hulls into mutual blocks it was never checked against. The shipped requirement
    // is zero, enforced by the acceptance gate on the forward-generated corpus, not here.
    expect(deadLevels.count <= 3, "legacy corpus: at most 3 levels reach a dead end (ship gate demands 0)")
    // Still true of the game as it stands, and the number the redesign exists to destroy:
    // the ship gate replaces this with `greedyRate < 15`.
    expect(greedyRate >= 90.0, "zero-thought policy still three-stars at least 90 % of runs")
    expect(parEqBoats == gen.count, "par still equals boat count on every level")

    if failures.isEmpty {
        print("")
        print("AUDIT OK — the measured baseline is unchanged.")
        return 0
    }
    print("")
    print("AUDIT FAILED — \(failures.count) assertion(s) broke.")
    return 1
}
