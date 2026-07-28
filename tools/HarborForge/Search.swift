import Foundation

/// Finds a witness line — a concrete sequence of taps that clears a board — using the
/// REAL engine for every successor, so a witness is valid by construction and can be
/// replayed on device as an integrity check.
///
/// Search is A* with `h = boats remaining`. That heuristic is admissible because every
/// boat needs at least one tap to leave, so the first goal node popped is a shortest
/// line. Hitting either cap REJECTS the seed rather than shipping an unproven par:
/// a capped search silently returning a non-minimum would make "greedy fails to reach
/// the optimum" trivially true on every board, which is the exact trap that made the old
/// verifier a difficulty-removal filter.
enum HJSearch {

    /// Canonical key. Two states with the same key are interchangeable for search: same
    /// hulls in the same places facing the same way, same tide, same ferry, and the same
    /// point in the world's repeating cycle (the tide flips every 3 ticks and each lane
    /// reverses on its own period, so the phase is part of the state).
    static func key(_ s: HJBoardState) -> String {
        var out = ""
        out.reserveCapacity(s.boats.count * 10 + 24)
        for b in s.boats.sorted(by: { $0.id < $1.id }) {
            out += "\(b.id),\(b.x),\(b.y),\(b.bow.rawValue),\(b.throttle);"
        }
        out += "|"
        out += s.tideHigh ? "H" : "L"
        out += "|\(s.ferry?.x ?? -1)"
        var cycle = s.tideEnabled ? 3 : 1
        for lane in s.currents where lane.period > 0 { cycle = lcm(cycle, lane.period) }
        out += "|\(s.taps % max(cycle, 1))"
        return out
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
    private static func lcm(_ a: Int, _ b: Int) -> Int { a / gcd(a, b) * b }

    private struct Node {
        var state: HJBoardState
        var parent: Int
        var move: Int
        var depth: Int
    }

    static func witness(from start: HJBoardState,
                        nodeCap: Int = 200_000,
                        depthCap: Int? = nil) -> [Int]? {
        if start.isCleared { return [] }
        let cap = depthCap ?? (4 * start.boats.count)

        var nodes: [Node] = [Node(state: start, parent: -1, move: -1, depth: 0)]
        var seen: Set<String> = [key(start)]

        // Bucket queue on f = depth + boats remaining. f only ever grows, so a plain
        // array of buckets is a correct priority queue here and costs O(1) per operation.
        var buckets: [[Int]] = Array(repeating: [], count: cap + start.boats.count + 2)
        buckets[start.boats.count].append(0)
        var f = 0

        while f < buckets.count {
            if buckets[f].isEmpty { f += 1; continue }
            let idx = buckets[f].removeLast()
            let node = nodes[idx]
            if node.depth >= cap { continue }

            for boat in node.state.boats {
                var next = node.state
                let outcome = HJEngine.tap(boatID: boat.id, state: &next)
                // A refusal spends a tick and can still change the world (ferry, tide,
                // drift), so it is a legal move — but only worth exploring when it
                // actually changed something.
                if case .invalid = outcome { continue }
                if next == node.state { continue }

                let k = key(next)
                if seen.contains(k) { continue }
                seen.insert(k)

                let child = Node(state: next, parent: idx, move: boat.id, depth: node.depth + 1)
                if next.isCleared {
                    var line: [Int] = []
                    var cursor = nodes.count
                    nodes.append(child)
                    while cursor > 0 {
                        line.append(nodes[cursor].move)
                        cursor = nodes[cursor].parent
                    }
                    return line.reversed()
                }
                if nodes.count >= nodeCap { return nil }
                nodes.append(child)
                let cf = child.depth + next.boats.count
                if cf < buckets.count { buckets[cf].append(nodes.count - 1) }
            }
        }
        return nil
    }

    /// Replay a line through the real engine and report whether it clears the board.
    static func replays(_ line: [Int], from start: HJBoardState) -> Bool {
        var state = start
        for id in line {
            if case .invalid = HJEngine.tap(boatID: id, state: &state) { return false }
        }
        return state.isCleared
    }
}

/// Search checks on two hand-authored boards whose answers are worked out by hand.
func forgeRunSearchChecks() -> Int {
    var failures = 0
    func expect(_ ok: Bool, _ what: String) {
        print(ok ? "PASS  \(what)" : "FAIL  \(what)")
        if !ok { failures += 1 }
    }

    // ---- Board A: solvable, and NOT in one tap per boat ------------------------------
    // 6x6. Boat 0 occupies (0,0)-(1,0) facing east with throttle 1. It has cleared the
    // board only once its trailing cell passes x = 6, so from x = 0 that is six taps of
    // one cell each. Boat 1 at (4,3)-(5,3) faces east with throttle 3 and is gone in one.
    // Nothing blocks anything, so the shortest line is 6 + 1 = 7 taps — against a boat
    // count of 2. That gap IS the redesign: the old par would have been 2.
    let a0 = HJBoat(id: 0, x: 0, y: 0, length: 2, isBarge: false, bow: .east, hullIndex: 0, anchoredBy: nil, throttle: 1)
    let a1 = HJBoat(id: 1, x: 4, y: 3, length: 2, isBarge: false, bow: .east, hullIndex: 1, anchoredBy: nil, throttle: 3)
    let boardA = HJBoardState(gridW: 6, gridH: 6, boats: [a0, a1], exitedIDs: [], sandbars: [],
                              currents: [], ferry: nil, tideEnabled: false, tideHigh: true,
                              basins: [], taps: 0, night: false)
    if let line = HJSearch.witness(from: boardA) {
        expect(HJSearch.replays(line, from: boardA), "board A: the witness replays to a cleared board")
        expect(line.count == 7, "board A: shortest line is 7 taps (found \(line.count))")
        expect(line.count > boardA.boats.count, "board A: par exceeds the boat count")
    } else {
        expect(false, "board A: a witness was found")
    }

    // ---- Board B: provably unsolvable ------------------------------------------------
    // 6x4. Boat 0 sits at (0,0)-(1,0) facing EAST, nose against a 2x2 barge at (2,0).
    // The barge is anchored to boat 0, so it cannot move until boat 0 leaves; boat 0
    // cannot move until the barge does. There is no basin to turn either of them around
    // and no current to shift them, so neither will ever move and the board can never
    // clear. The search must return nil rather than a line.
    let c0 = HJBoat(id: 0, x: 0, y: 0, length: 2, isBarge: false, bow: .east, hullIndex: 0, anchoredBy: nil, throttle: 2)
    let b1 = HJBoat(id: 1, x: 2, y: 0, length: 2, isBarge: true, bow: .west, hullIndex: 1, anchoredBy: 0, throttle: 2)
    let boardB = HJBoardState(gridW: 6, gridH: 4, boats: [c0, b1], exitedIDs: [], sandbars: [],
                              currents: [], ferry: nil, tideEnabled: false, tideHigh: true,
                              basins: [], taps: 0, night: false)
    let lineB = HJSearch.witness(from: boardB)
    expect(lineB == nil, "board B: no witness exists (mutual block, no basin)")

    // ---- The search never returns a line that does not clear the board ---------------
    var checked = 0
    var bad = 0
    for chapter in 0..<HJCatalog.chapters.count {
        for level in stride(from: 0, to: HJCatalog.levelsPerChapter, by: 7) {
            let config = HJCatalog.config(chapter: chapter, level: level)
            for salt in 0..<6 {
                let seed = HJCatalog.seed(chapter: chapter, level: level) &+ UInt64(salt) &* 0x2545F4914F6CDD1D
                guard let b = HJForge.board(seed: seed, config: config) else { continue }
                guard let line = HJSearch.witness(from: b) else { continue }
                checked += 1
                if !HJSearch.replays(line, from: b) { bad += 1 }
            }
        }
    }
    print("witnesses replayed: \(checked)")
    expect(checked > 0, "the search solves at least some forward-generated boards")
    expect(bad == 0, "every witness the search returns replays to a cleared board")

    if failures == 0 { print("SEARCH OK"); return 0 }
    print("SEARCH FAILED — \(failures) assertion(s)")
    return 1
}
