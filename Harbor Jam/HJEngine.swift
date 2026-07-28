import Foundation

/// Full, deterministic play-state of one level. Value type — undo is a snapshot stack.
struct HJBoardState: Codable, Equatable {
    var gridW: Int
    var gridH: Int
    var boats: [HJBoat]
    var exitedIDs: [Int]
    var sandbars: [HJCell]
    var currents: [HJCurrentLane]
    var ferry: HJFerry?
    var tideEnabled: Bool
    var tideHigh: Bool
    var basins: [HJCell]      // enter one and the bow flips 180°
    var taps: Int
    var night: Bool

    var isCleared: Bool { boats.isEmpty }

    func boat(withID id: Int) -> HJBoat? { boats.first(where: { $0.id == id }) }

    func occupied(excluding boatID: Int? = nil) -> Set<HJCell> {
        var out = Set<HJCell>()
        for b in boats where b.id != boatID {
            for c in b.cells { out.insert(c) }
        }
        return out
    }

    func ferryCells() -> Set<HJCell> {
        guard let f = ferry else { return [] }
        var out = Set<HJCell>()
        for i in 0..<f.length {
            let x = (f.x + i) % gridW
            out.insert(HJCell(x: x, y: f.row))
        }
        return out
    }

    func solidCells(excluding boatID: Int? = nil) -> Set<HJCell> {
        var out = occupied(excluding: boatID)
        out.formUnion(ferryCells())
        if tideEnabled && !tideHigh {
            out.formUnion(sandbars)
        }
        return out
    }

    func inBounds(_ c: HJCell) -> Bool {
        c.x >= 0 && c.x < gridW && c.y >= 0 && c.y < gridH
    }

    func isAnchored(_ boat: HJBoat) -> Bool {
        guard let key = boat.anchoredBy else { return false }
        return !exitedIDs.contains(key)
    }
}

/// Why a boat refused to move. The board draws each of these differently — collapsing
/// them into one shake is what made the harbor feel arbitrary.
enum HJBlockReason: Int, Codable, Equatable {
    case hull       // another boat is in the way
    case sandbar    // the tide is out and a bar is exposed
    case ferry      // the ferry occupies the next cell
    case edge       // the harbour wall, on a side the bow does not face
}

enum HJTapOutcome: Equatable {
    case exited(boatID: Int)
    case moved(boatID: Int, distance: Int)
    case blocked(reason: HJBlockReason)   // boat could not move at all — still costs a tick
    case anchored                          // locked by buoy chain — still costs a tick
    case invalid                           // no such boat; nothing happens, nothing ticks
}

/// Where a tap would put a boat, computed once and used by both the move and the ghost
/// the player sees on a long press. A preview that disagrees with the move is the classic
/// "the game lied to me" bug, so there is exactly one walk and both callers share it.
struct HJMovePreview: Equatable {
    var landing: [HJCell]           // cells the hull would occupy; empty when it exits
    var exits: Bool
    var distance: Int
    var stopReason: HJBlockReason?  // nil when it simply ran out of throttle or came about
    var bowAfter: HJDirection       // differs from the bow only after a turning basin
    var enteredBasin: Bool
}

enum HJEngine {

    /// The leading cells of a hull — the ones that meet whatever is ahead of it.
    static func bowCells(of boat: HJBoat) -> [HJCell] {
        let cells = boat.cells
        switch boat.bow {
        case .east:  return cells.filter { $0.x == boat.x + boat.width - 1 }
        case .west:  return cells.filter { $0.x == boat.x }
        case .south: return cells.filter { $0.y == boat.y + boat.height - 1 }
        case .north: return cells.filter { $0.y == boat.y }
        }
    }

    /// The single walk. Advances at most `boat.throttle` cells, stopping early on an
    /// obstacle, on leaving the board, or on nosing into a turning basin — which also
    /// turns the hull about. Everything else in this engine is a thin wrapper on it.
    private static func marchDetail(boat: HJBoat, state: HJBoardState)
        -> (boat: HJBoat, distance: Int, exits: Bool, stopReason: HJBlockReason?, enteredBasin: Bool) {

        let solids = state.solidCells(excluding: boat.id)
        let basins = Set(state.basins)
        var current = boat
        var steps = 0

        while steps < boat.throttle {
            var candidate = current
            candidate.x += boat.bow.dx
            candidate.y += boat.bow.dy
            let cells = candidate.cells
            let inside = cells.filter { state.inBounds($0) }

            if inside.contains(where: { solids.contains($0) }) {
                let reason = steps == 0 ? blockReason(boat: current, state: state, solids: solids) : nil
                return (current, steps, false, reason, false)
            }
            let outside = cells.filter { !state.inBounds($0) }
            if !outside.isEmpty {
                let legal = outside.allSatisfy { c in
                    switch boat.bow {
                    case .east:  return c.x >= state.gridW
                    case .west:  return c.x < 0
                    case .south: return c.y >= state.gridH
                    case .north: return c.y < 0
                    }
                }
                if !legal {
                    let reason = steps == 0 ? HJBlockReason.edge : nil
                    return (current, steps, false, reason, false)
                }
            }

            current = candidate
            steps += 1
            if inside.isEmpty { return (current, steps, true, nil, false) }

            // A basin catches the hull the moment its bow enters, and turns it about.
            if !basins.isEmpty && bowCells(of: current).contains(where: { basins.contains($0) }) {
                current.bow = boat.bow.opposite
                return (current, steps, false, nil, true)
            }
        }
        return (current, steps, false, nil, false)
    }

    /// Where a tap would land this boat, without touching the board.
    static func march(boat: HJBoat, state: HJBoardState) -> HJMovePreview {
        let r = marchDetail(boat: boat, state: state)
        return HJMovePreview(landing: r.exits ? [] : r.boat.cells,
                             exits: r.exits,
                             distance: r.distance,
                             stopReason: r.stopReason,
                             bowAfter: r.boat.bow,
                             enteredBasin: r.enteredBasin)
    }

    /// Where this boat will actually be once the tap is resolved AND the world has ticked.
    ///
    /// This runs the real tap on a copy rather than reporting the march landing, because
    /// the tick that follows a move can drift the very boat that just moved: a hull set
    /// down in a current lane is pushed a cell before the player's finger leaves the
    /// glass. A ghost drawn at the march landing would be wrong in exactly the cases the
    /// lane exists to teach. `distance`, `stopReason` and `enteredBasin` still describe
    /// the tap itself, so the board can say *why* the boat stops where it does.
    static func preview(boatID: Int, state: HJBoardState) -> HJMovePreview {
        guard let boat = state.boat(withID: boatID) else {
            return HJMovePreview(landing: [], exits: false, distance: 0,
                                 stopReason: nil, bowAfter: .north, enteredBasin: false)
        }
        if state.isAnchored(boat) {
            return HJMovePreview(landing: boat.cells, exits: false, distance: 0,
                                 stopReason: nil, bowAfter: boat.bow, enteredBasin: false)
        }
        let walk = marchDetail(boat: boat, state: state)
        var probe = state
        _ = tap(boatID: boatID, state: &probe)
        let settled = probe.boat(withID: boatID)
        return HJMovePreview(landing: settled?.cells ?? [],
                             exits: settled == nil,
                             distance: walk.distance,
                             stopReason: walk.stopReason,
                             bowAfter: settled?.bow ?? walk.boat.bow,
                             enteredBasin: walk.enteredBasin)
    }

    /// Resolve tapping a boat. Mutates `state` in place. Fully deterministic.
    static func tap(boatID: Int, state: inout HJBoardState) -> HJTapOutcome {
        guard let boat = state.boat(withID: boatID) else { return .invalid }
        if state.isAnchored(boat) {
            tickWorld(&state)
            return .anchored
        }

        let r = marchDetail(boat: boat, state: state)

        if r.distance == 0 {
            let reason = r.stopReason ?? .edge
            tickWorld(&state)
            return .blocked(reason: reason)
        }

        if r.exits {
            state.boats.removeAll { $0.id == boatID }
            state.exitedIDs.append(boatID)
            tickWorld(&state)
            return .exited(boatID: boatID)
        }

        if let idx = state.boats.firstIndex(where: { $0.id == boatID }) {
            state.boats[idx] = r.boat
        }
        tickWorld(&state)
        return .moved(boatID: boatID, distance: r.distance)
    }

    /// World updates that run on EVERY tap the player spends, including one that moved
    /// nothing. Before this existed the ferry only advanced when some boat successfully
    /// sailed, so a board whose remaining boats were all blocked by the ferry could never
    /// change again. It also removes free probing: tapping every hull to read the answer
    /// off the engine now costs the same as playing.
    static func tickWorld(_ state: inout HJBoardState) {
        state.taps += 1
        if state.tideEnabled && state.taps % 3 == 0 {
            state.tideHigh.toggle()
        }
        advanceFerry(&state)
        applyCurrents(&state)
    }

    /// Classify why `boat` could not advance a single cell, by re-probing that first step.
    /// Hull before ferry before sandbar, because a cell can belong to more than one of
    /// them and the nearest physical explanation is the one worth telling the player.
    static func blockReason(boat: HJBoat, state: HJBoardState, solids: Set<HJCell>) -> HJBlockReason {
        var candidate = boat
        candidate.x += boat.bow.dx
        candidate.y += boat.bow.dy
        let cells = candidate.cells

        let offending = cells.filter { state.inBounds($0) && solids.contains($0) }
        if !offending.isEmpty {
            let hulls = state.occupied(excluding: boat.id)
            if offending.contains(where: { hulls.contains($0) }) { return .hull }
            let ferry = state.ferryCells()
            if offending.contains(where: { ferry.contains($0) }) { return .ferry }
            return .sandbar
        }
        return .edge
    }

    /// Every non-barge hull sitting in a current lane drifts one cell, on every tick —
    /// not only the boat the player just touched. This is what makes the harbor change
    /// without the player's consent, and therefore what stops a reachable state from
    /// always being at least as easy as the start.
    ///
    /// Lanes resolve far-side-first: the hull closest to the edge the current pushes
    /// toward moves before the one behind it, so a queue in a lane shuffles along instead
    /// of the leader blocking everyone.
    static func applyCurrents(_ state: inout HJBoardState) {
        guard !state.currents.isEmpty else { return }
        for lane in state.currents {
            let push = lane.effectivePush(atTick: state.taps)
            let residents = state.boats.filter { boat in
                !boat.isBarge && boat.cells.contains { lane.isRow ? $0.y == lane.index : $0.x == lane.index }
            }
            let ordered = residents.sorted { a, b in
                switch push {
                case .east:  return a.x > b.x
                case .west:  return a.x < b.x
                case .south: return a.y > b.y
                case .north: return a.y < b.y
                }
            }
            for boat in ordered {
                guard let idx = state.boats.firstIndex(where: { $0.id == boat.id }) else { continue }
                var moved = state.boats[idx]
                moved.x += push.dx
                moved.y += push.dy
                let solids = state.solidCells(excluding: moved.id)
                guard moved.cells.allSatisfy({ state.inBounds($0) && !solids.contains($0) }) else { continue }
                state.boats[idx] = moved
            }
        }
    }

    private static func advanceFerry(_ state: inout HJBoardState) {
        guard var f = state.ferry else { return }
        let occ = state.occupied()
        let sand: Set<HJCell> = (state.tideEnabled && !state.tideHigh) ? Set(state.sandbars) : []
        var advanced = 0
        var x = f.x
        while advanced < f.stride {
            let nx = (x + 1) % state.gridW
            var free = true
            for i in 0..<f.length {
                let cell = HJCell(x: (nx + i) % state.gridW, y: f.row)
                if occ.contains(cell) || sand.contains(cell) { free = false; break }
            }
            if !free { break }   // ferry waits, deterministic
            x = nx
            advanced += 1
        }
        f.x = x
        state.ferry = f
    }

    private static func applyCurrent(_ state: inout HJBoardState, boatID: Int) {
        guard let idx = state.boats.firstIndex(where: { $0.id == boatID }) else { return }
        let boat = state.boats[idx]
        if boat.isBarge { return }   // barges block currents and are unaffected
        // Find first lane containing any boat cell
        guard let lane = state.currents.first(where: { lane in
            boat.cells.contains { lane.isRow ? $0.y == lane.index : $0.x == lane.index }
        }) else { return }
        var moved = boat
        moved.x += lane.push.dx
        moved.y += lane.push.dy
        let solids = state.solidCells(excluding: boatID)
        let cells = moved.cells
        guard cells.allSatisfy({ state.inBounds($0) && !solids.contains($0) }) else { return }
        state.boats[idx] = moved
    }

}
