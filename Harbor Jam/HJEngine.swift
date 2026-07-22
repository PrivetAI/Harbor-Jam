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
    var tugTokens: Int
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

enum HJTapOutcome: Equatable {
    case exited(boatID: Int)
    case moved(boatID: Int, distance: Int)
    case blocked          // boat could not move at all (shake, no move cost)
    case anchored         // locked by buoy chain
    case invalid
}

enum HJEngine {

    /// Resolve tapping a boat. Mutates `state` in place. Fully deterministic.
    static func tap(boatID: Int, state: inout HJBoardState) -> HJTapOutcome {
        guard let boat = state.boat(withID: boatID) else { return .invalid }
        if state.isAnchored(boat) { return .anchored }

        let solids = state.solidCells(excluding: boatID)
        let dx = boat.bow.dx, dy = boat.bow.dy

        // March forward one cell at a time until blocked or fully off the board.
        var steps = 0
        var exited = false
        var cx = boat.x, cy = boat.y
        while true {
            let nx = cx + dx, ny = cy + dy
            var candidate = boat
            candidate.x = nx
            candidate.y = ny
            let cells = candidate.cells
            let insideCells = cells.filter { state.inBounds($0) }
            // blocked if any in-bounds cell of the candidate is solid
            if insideCells.contains(where: { solids.contains($0) }) { break }
            // If a cell left the board on a side that is NOT the bow direction, that's illegal;
            // by construction straight movement only sheds cells past the bow-side edge.
            let outCells = cells.filter { !state.inBounds($0) }
            if !outCells.isEmpty {
                // verify all out-of-bounds cells are beyond the bow-side edge
                let legal = outCells.allSatisfy { c in
                    switch boat.bow {
                    case .east: return c.x >= state.gridW
                    case .west: return c.x < 0
                    case .south: return c.y >= state.gridH
                    case .north: return c.y < 0
                    }
                }
                if !legal { break }
            }
            cx = nx; cy = ny
            steps += 1
            if insideCells.isEmpty { exited = true; break }
            if steps > state.gridW + state.gridH + 4 { break } // safety bound
        }

        if steps == 0 { return .blocked }

        if exited {
            state.boats.removeAll { $0.id == boatID }
            state.exitedIDs.append(boatID)
            afterMove(&state, movedBoatID: nil)
            return .exited(boatID: boatID)
        } else {
            if let idx = state.boats.firstIndex(where: { $0.id == boatID }) {
                state.boats[idx].x = cx
                state.boats[idx].y = cy
            }
            afterMove(&state, movedBoatID: boatID)
            return .moved(boatID: boatID, distance: steps)
        }
    }

    /// Post-move world updates: tap counter, tide toggle, ferry advance, current push.
    private static func afterMove(_ state: inout HJBoardState, movedBoatID: Int?) {
        state.taps += 1
        if state.tideEnabled && state.taps % 3 == 0 {
            state.tideHigh.toggle()
            // A tide drop never traps a boat mid-sandbar: boats and sandbars never overlap
            // because sandbar cells are excluded from all placements and rest positions.
        }
        advanceFerry(&state)
        if let id = movedBoatID {
            applyCurrent(&state, boatID: id)
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

    /// Tug power-up: rotate a boat 90° clockwise in place around its top-left cell.
    static func tugRotate(boatID: Int, state: inout HJBoardState) -> Bool {
        guard state.tugTokens > 0,
              let idx = state.boats.firstIndex(where: { $0.id == boatID }) else { return false }
        let boat = state.boats[idx]
        if state.isAnchored(boat) { return false }
        var rotated = boat
        rotated.bow = boat.bow.rotatedCW
        if boat.isBarge {
            // footprint unchanged, bow re-aims — always legal
            state.boats[idx] = rotated
            state.tugTokens -= 1
            return true
        }
        let solids = state.solidCells(excluding: boatID)
        let cells = rotated.cells
        guard cells.allSatisfy({ state.inBounds($0) && !solids.contains($0) }) else { return false }
        state.boats[idx] = rotated
        state.tugTokens -= 1
        return true
    }
}
