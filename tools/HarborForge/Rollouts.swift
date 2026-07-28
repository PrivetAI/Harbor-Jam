import Foundation

// MARK: - Rollout RNG

/// SplitMix64, deliberately separate from the app's `HJRandom` so rollout noise can
/// never perturb level generation.
struct ForgeRNG {
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
}

// MARK: - Tap classification

enum ForgeTapKind { case exits, advances, noop }

/// Probe one tap on a COPY of the state and report what it would do.
func forgeClassify(boatID: Int, state: HJBoardState) -> ForgeTapKind {
    var probe = state
    switch HJEngine.tap(boatID: boatID, state: &probe) {
    case .exited: return .exits
    case .moved: return .advances
    default: return .noop
    }
}

/// True when a tap leaves the board bit-for-bit identical — i.e. free probing.
func forgeTapIsInert(boatID: Int, state: HJBoardState) -> Bool {
    var probe = state
    _ = HJEngine.tap(boatID: boatID, state: &probe)
    return probe == state
}

/// Split every boat on the board by what tapping it would do right now.
func forgeOptions(_ state: HJBoardState) -> (exits: [Int], advances: [Int], noops: [Int]) {
    var exits: [Int] = [], advances: [Int] = [], noops: [Int] = []
    for b in state.boats {
        switch forgeClassify(boatID: b.id, state: state) {
        case .exits: exits.append(b.id)
        case .advances: advances.append(b.id)
        case .noop: noops.append(b.id)
        }
    }
    return (exits, advances, noops)
}

// MARK: - Rollout policies

struct ForgeRollout {
    var cleared: Bool
    var moves: Int
    var deadlocked: Bool
}

/// Safety bound: no honest line is anywhere near this long, so hitting it means the
/// policy is looping and the run is reported as neither cleared nor deadlocked.
private let forgeStepCap = 400

/// POLICY A — the zero-thought strategy. Only ever commits a tap that exits a boat,
/// chosen uniformly at random. Never plans, never looks ahead, never undoes.
///
/// Under the shipped rules this policy is a *complete* solver, because exiting only
/// removes occupancy and so can never spoil another boat's line. Measuring how often
/// it three-stars is therefore the single honest measure of whether the game contains
/// a puzzle at all.
func forgeRolloutA(start: HJBoardState, rng: inout ForgeRNG) -> ForgeRollout {
    var state = start
    var steps = 0
    while !state.isCleared && steps < forgeStepCap {
        steps += 1
        let opts = forgeOptions(state)
        guard !opts.exits.isEmpty else {
            return ForgeRollout(cleared: false, moves: state.taps, deadlocked: false)
        }
        _ = HJEngine.tap(boatID: opts.exits[rng.int(opts.exits.count)], state: &state)
    }
    return ForgeRollout(cleared: state.isCleared, moves: state.taps, deadlocked: false)
}

/// POLICY B — a careless human with no undo. Commits ANY state-changing tap, preferring
/// an exit when one is offered. Reports a deadlock when the board is not cleared and
/// neither an exit nor an advance is available: nothing the player can press does
/// anything, and only undo or restart gets them out.
func forgeRolloutB(start: HJBoardState, rng: inout ForgeRNG) -> ForgeRollout {
    var state = start
    var steps = 0
    while !state.isCleared && steps < forgeStepCap {
        steps += 1
        let opts = forgeOptions(state)
        if !opts.exits.isEmpty {
            _ = HJEngine.tap(boatID: opts.exits[rng.int(opts.exits.count)], state: &state)
        } else if !opts.advances.isEmpty {
            _ = HJEngine.tap(boatID: opts.advances[rng.int(opts.advances.count)], state: &state)
        } else {
            return ForgeRollout(cleared: false, moves: state.taps, deadlocked: true)
        }
    }
    return ForgeRollout(cleared: state.isCleared, moves: state.taps, deadlocked: false)
}
