import Foundation

/// Assertions on the frozen engine. These guard the invariants the rest of the redesign
/// leans on; if one of them breaks, every baked witness is worthless.
func forgeRunEngineChecks() -> Int {
    var failures = 0
    func expect(_ ok: Bool, _ what: String) {
        print(ok ? "PASS  \(what)" : "FAIL  \(what)")
        if !ok { failures += 1 }
    }

    // ---- 1. preview and tap must never disagree ------------------------------------
    // The ghost hull the player sees on a long press is drawn from `preview`; the move
    // is performed by `tap`. If they can differ anywhere, the game lies to the player.
    var pairsChecked = 0
    var mismatches: [String] = []
    for chapter in 0..<HJCatalog.chapters.count {
        for level in 0..<HJCatalog.levelsPerChapter {
            guard let g = HJGenerator.campaignLevel(chapter: chapter, level: level) else { continue }
            var rng = ForgeRNG(seed: UInt64(chapter &* 977 &+ level))
            var state = g.start
            for _ in 0..<12 {
                guard !state.boats.isEmpty else { break }
                for boat in state.boats {
                    let p = HJEngine.preview(boatID: boat.id, state: state)
                    var probe = state
                    let outcome = HJEngine.tap(boatID: boat.id, state: &probe)
                    pairsChecked += 1

                    switch outcome {
                    case .exited:
                        if !p.exits { mismatches.append("\(chapter)-\(level) boat \(boat.id): tap exited, preview did not") }
                    case .moved(_, let distance):
                        let landed = probe.boat(withID: boat.id)?.cells ?? []
                        if p.exits { mismatches.append("\(chapter)-\(level) boat \(boat.id): preview exited, tap moved") }
                        if p.distance != distance { mismatches.append("\(chapter)-\(level) boat \(boat.id): distance \(p.distance) vs \(distance)") }
                        if Set(p.landing) != Set(landed) { mismatches.append("\(chapter)-\(level) boat \(boat.id): landing cells differ") }
                        if probe.boat(withID: boat.id)?.bow != p.bowAfter { mismatches.append("\(chapter)-\(level) boat \(boat.id): bow differs") }
                    case .blocked, .anchored:
                        if p.distance != 0 { mismatches.append("\(chapter)-\(level) boat \(boat.id): preview moved \(p.distance), tap refused") }
                    case .invalid:
                        break
                    }
                }
                // advance the board so later plies are checked too
                let opts = forgeOptions(state)
                let pick = opts.exits.first ?? opts.advances.first ?? opts.noops.first
                guard let id = pick else { break }
                _ = HJEngine.tap(boatID: id, state: &state)
                _ = rng.next()
            }
        }
    }
    expect(mismatches.isEmpty, "preview agrees with tap on \(pairsChecked) (board, boat) pairs")
    for m in mismatches.prefix(5) { print("        \(m)") }

    // ---- 2. a current lane drifts EVERY resident, not just the boat just moved -------
    let laneBoats = [
        HJBoat(id: 0, x: 1, y: 2, length: 2, isBarge: false, bow: .north, hullIndex: 0, anchoredBy: nil, throttle: 1),
        HJBoat(id: 1, x: 4, y: 2, length: 2, isBarge: false, bow: .north, hullIndex: 1, anchoredBy: nil, throttle: 1),
    ]
    var laneState = HJBoardState(gridW: 8, gridH: 8, boats: laneBoats, exitedIDs: [], sandbars: [],
                                 currents: [HJCurrentLane(isRow: false, index: 1, push: .south, period: 0)],
                                 ferry: nil, tideEnabled: false, tideHigh: true, basins: [], taps: 0, night: false)
    // Boat 0 occupies column 1 (bow north, length 2 -> cells (1,2),(1,3)); boat 1 is in column 4.
    let before0 = laneState.boat(withID: 0)!.y
    let before1 = laneState.boat(withID: 1)!.y
    HJEngine.applyCurrents(&laneState)
    let after0 = laneState.boat(withID: 0)!.y
    let after1 = laneState.boat(withID: 1)!.y
    expect(after0 == before0 + 1, "a hull in the lane drifts with the current")
    expect(after1 == before1, "a hull outside the lane does not drift")

    // ---- 3. a turning basin reverses the bow and preserves the footprint -------------
    let runner = HJBoat(id: 0, x: 0, y: 0, length: 3, isBarge: false, bow: .east, hullIndex: 0, anchoredBy: nil, throttle: 3)
    var basinState = HJBoardState(gridW: 8, gridH: 8, boats: [runner], exitedIDs: [], sandbars: [],
                                  currents: [], ferry: nil, tideEnabled: false, tideHigh: true,
                                  basins: [HJCell(x: 4, y: 0)], taps: 0, night: false)
    let footprintBefore = runner.cells.count
    let outcome = HJEngine.tap(boatID: 0, state: &basinState)
    if let after = basinState.boat(withID: 0) {
        expect(after.bow == .west, "a boat nosing into a basin comes about")
        expect(after.cells.count == footprintBefore, "the basin turn preserves the footprint")
        expect(after.x == 2 && after.y == 0, "the boat stops in the basin rather than sailing past it")
    } else {
        expect(false, "the boat survived the basin (outcome was \(outcome))")
    }

    // ---- 4. throttle actually bounds the march --------------------------------------
    let slow = HJBoat(id: 0, x: 0, y: 0, length: 2, isBarge: false, bow: .east, hullIndex: 0, anchoredBy: nil, throttle: 2)
    var slowState = HJBoardState(gridW: 8, gridH: 8, boats: [slow], exitedIDs: [], sandbars: [],
                                 currents: [], ferry: nil, tideEnabled: false, tideHigh: true,
                                 basins: [], taps: 0, night: false)
    let slowOutcome = HJEngine.tap(boatID: 0, state: &slowState)
    if case .moved(_, let d) = slowOutcome {
        expect(d == 2, "a throttle-2 hull advances exactly 2 cells on an open board")
        expect(slowState.boat(withID: 0) != nil, "a throttle-bounded hull does not reach the edge in one tap")
    } else {
        expect(false, "throttle-2 hull on an open board should move, got \(slowOutcome)")
    }

    if failures == 0 { print("ENGINE OK"); return 0 }
    print("ENGINE FAILED — \(failures) assertion(s)")
    return 1
}
