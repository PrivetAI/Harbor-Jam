import Foundation

struct ForgeShiftReport {
    var port: Int
    var shift: Int
    var def: HJShiftDef
    var smart: ForgeResult
    var greedy: ForgeResult
    var random: ForgeResult
}

/// Accept a candidate only where greedy underperforms.
///
/// This is the inverse of the generator this game had before, which built a
/// board by undoing a solution and then verified the solution still replayed —
/// a filter that removed every seed where a mechanic would have mattered. Here
/// nothing is verified against a known answer; candidates are simply thrown away
/// unless the dumb policy measurably does worse on them.
func forgeAccept(port: Int, shift: Int, maxSalts: Int = 220) -> ForgeShiftReport? {
    for salt in 0..<maxSalts {
        var def = forgeShift(port: port, shift: shift, salt: salt)
        let s = forgeRun(def: def, upgrades: .zero, policy: .smart, seed: 1)
        // A shift the reference policy cannot survive is not a shift.
        //
        // It is allowed to drop one ship. S is a heuristic, not optimal play:
        // insisting it goes flawless tunes the shipped game to "a mediocre bot
        // never slips", which is far easier than a player who actually plans.
        // Losing two of three reputation is still a comfortable margin.
        guard !s.failed, s.counters.shipsLost <= 1 else { continue }

        def.parTicks = s.endTick * HJTuning.parCushionPercent / 100
        // Re-run so the reference score is measured against the par it just set.
        let calibrated = forgeRun(def: def, upgrades: .zero, policy: .smart, seed: 1)
        def.target3 = calibrated.score * HJTuning.target3Percent / 100
        def.target2 = calibrated.score * HJTuning.target2Percent / 100

        let g = forgeRun(def: def, upgrades: .zero, policy: .greedy, seed: 2)
        let r = forgeRun(def: def, upgrades: .zero, policy: .random, seed: 3)

        // Ports 1 and 2 teach, and are allowed to be gentle — demanding that
        // random play fail there would reject every board a beginner could
        // learn on, which is what the first measurement did.
        if port >= 3 {
            if !(g.failed || g.stars < 3) { continue }
            if r.stars >= 3 { continue }
        }

        return ForgeShiftReport(port: port, shift: shift, def: def,
                                smart: calibrated, greedy: g, random: r)
    }
    return nil
}

private func median(_ xs: [Int]) -> Double {
    guard !xs.isEmpty else { return 0 }
    let s = xs.sorted()
    return s.count % 2 == 1 ? Double(s[s.count / 2])
                            : Double(s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

func forgeGate() -> (ok: Bool, text: String, reports: [ForgeShiftReport]) {
    var reports: [ForgeShiftReport] = []
    var unbuildable: [String] = []
    for port in 1...HJCatalog.portCount {
        for shift in 1...HJCatalog.shiftsPerPort {
            if let r = forgeAccept(port: port, shift: shift) {
                reports.append(r)
            } else {
                unbuildable.append("\(port)-\(shift)")
            }
        }
    }

    func pct(_ n: Int, _ d: Int) -> Double { d == 0 ? 0 : Double(n) * 100 / Double(d) }
    let late = reports.filter { $0.port >= 3 }
    let veryLate = reports.filter { $0.port >= 5 }

    let smartClears = reports.filter { $0.smart.stars >= 1 }.count
    let greedyThreeLate = late.filter { $0.greedy.stars == 3 }.count
    // Can greedy even reach two stars? target2 is 70 % of the reference score,
    // so this is a real threshold rather than one defined from G's own result.
    let greedyBelowTwoVeryLate = veryLate.filter { $0.greedy.score < $0.def.target2 }.count
    let greedyFailedVeryLate = veryLate.filter { $0.greedy.failed }.count
    let randomThree = late.filter { $0.random.stars == 3 }.count

    let medS = median(late.map { $0.smart.score })
    let medG = median(late.map { $0.greedy.score })
    let ratio = medG <= 0 ? Double.infinity : medS / medG

    let groundingsFromPort2 = reports.filter { $0.port >= 2 }
        .reduce(0) { $0 + $1.smart.counters.groundings }
    let channelUseLate = late.map {
        $0.smart.endTick == 0 ? 0 : $0.smart.counters.channelBusyTicks * 100 / $0.smart.endTick
    }
    let medChannel = median(channelUseLate)
    let mismatchFromPort4 = reports.filter { $0.port >= 4 }
        .reduce(0) { $0 + $1.smart.counters.mismatchedUnloads }

    var clauses: [(String, Bool, String)] = []
    clauses.append(("all shifts generate", unbuildable.isEmpty,
                    "\(reports.count)/\(HJCatalog.totalShifts)"
                        + (unbuildable.isEmpty ? "" : " missing: " + unbuildable.joined(separator: " "))))
    clauses.append(("S clears every shift", smartClears == reports.count,
                    "\(smartClears)/\(reports.count)"))
    // Deliberately NOT "S three-stars >= 80 %": target3 is calibrated at 92 % of
    // S's own score, so that clause is true by construction and measures nothing.
    clauses.append(("G misses two stars >= 80 % from port 5",
                    pct(greedyBelowTwoVeryLate, veryLate.count) >= 80,
                    String(format: "%.1f %%", pct(greedyBelowTwoVeryLate, veryLate.count))))
    clauses.append(("G three-stars <= 25 % from port 3", pct(greedyThreeLate, late.count) <= 25,
                    String(format: "%.1f %%", pct(greedyThreeLate, late.count))))
    clauses.append(("G fails >= 30 % from port 5", pct(greedyFailedVeryLate, veryLate.count) >= 30,
                    String(format: "%.1f %%", pct(greedyFailedVeryLate, veryLate.count))))
    clauses.append(("R three-stars nothing from port 3", randomThree == 0, "\(randomThree)"))
    clauses.append(("median S >= 1.35x median G", ratio >= 1.35,
                    ratio.isFinite ? String(format: "%.2fx", ratio) : "inf"))
    clauses.append(("groundings live from port 2", groundingsFromPort2 > 0, "\(groundingsFromPort2)"))
    clauses.append(("channel busy >= 25 % from port 3", medChannel >= 25,
                    String(format: "%.0f %% median", medChannel)))
    clauses.append(("gear mismatch lives from port 4", mismatchFromPort4 > 0, "\(mismatchFromPort4)"))

    var out = "=== HARBOR JAM — ACCEPTANCE GATE ===\n"
    var ok = true
    for (name, pass, detail) in clauses {
        out += "\(pass ? "PASS" : "FAIL")  \(name)  [\(detail)]\n"
        if !pass { ok = false }
    }

    out += "\n--- per-port detail (policy S / policy G) ---\n"
    for port in 1...HJCatalog.portCount {
        let rs = reports.filter { $0.port == port }
        guard !rs.isEmpty else { out += "port \(port): NONE GENERATED\n"; continue }
        let s3 = rs.filter { $0.smart.stars == 3 }.count
        let g3 = rs.filter { $0.greedy.stars == 3 }.count
        let gf = rs.filter { $0.greedy.failed }.count
        out += String(format: "port %d  shifts=%2d  S3=%2d  G3=%2d  Gfail=%2d  medS=%6.0f medG=%6.0f\n",
                      port, rs.count, s3, g3, gf,
                      median(rs.map { $0.smart.score }), median(rs.map { $0.greedy.score }))
    }

    out += ok ? "\nGATE PASSED\n" : "\nGATE FAILED — retune HJTuning / HJCatalog.ports and run again\n"
    return (ok, out, reports)
}
