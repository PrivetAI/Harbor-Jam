import Foundation

/// There is no XCTest target in this project and none is wanted — the harness
/// binary is the test surface, because the same binary also has to run the
/// acceptance gate against the very same simulation the app ships.
enum SimTests {
    static var failures: [String] = []
    static let caseCount = 10

    static func expect(_ cond: Bool, _ label: String) {
        if !cond { failures.append(label) }
    }

    static func expectEqual<T: Equatable>(_ a: T, _ b: T, _ label: String) {
        if a != b { failures.append("\(label): got \(a), want \(b)") }
    }

    // MARK: - Fixtures

    static func harbour(slots: [QLSlot], channel: Int = 10,
                        amplitude: Int = 0, step: Int = 0,
                        roadstead: Int = 4) -> QLHarborDef {
        QLHarborDef(slots: slots, channelTransitTicks: channel,
                    tideAmplitude: amplitude, tideStepTicks: step,
                    roadsteadCapacity: roadstead)
    }

    static func ship(id: Int = 1, length: Int = 2, draft: Int = 1,
                     cargo: QLCargo = .container, tons: Int = 4,
                     patience: Int = 1000, vip: Bool = false) -> QLShip {
        QLShip(id: id, length: length, draft: draft, cargo: cargo, tons: tons,
               patienceTicks: patience, isVIP: vip)
    }

    static func shift(harbor: QLHarborDef, arrivals: [QLArrival],
                      outages: [QLSlotOutage] = [], storms: [QLStormWindow] = [],
                      par: Int = 100_000) -> QLShiftDef {
        QLShiftDef(port: 1, shift: 1, harbor: harbor, arrivals: arrivals,
                   outages: outages, storms: storms,
                   parTicks: par, target2: 0, target3: Int.max)
    }

    // MARK: - Runner

    static func run() -> Bool {
        failures = []
        testBerthLegality()
        testChannelIsExclusive()
        testTideTriangleWave()
        testGroundingHoldsTheBerth()
        testMismatchedGearCostsMore()
        testPatienceOnlyBurnsWhileWaiting()
        testRoadsteadOverflowLosesShip()
        testSlotsFreeAtStartOfDeparture()
        testUpgradesApply()
        testDeterminism()
        for f in failures { print("FAIL  \(f)") }
        print(failures.isEmpty
              ? "SIM TESTS OK (\(caseCount) cases)"
              : "SIM TESTS FAILED (\(failures.count))")
        return failures.isEmpty
    }

    // MARK: - Cases

    static func testBerthLegality() {
        let quay = harbour(slots: [QLSlot(depth: 5, equipment: .crane),
                                   QLSlot(depth: 5, equipment: .crane),
                                   QLSlot(depth: 2, equipment: .crane)])
        var sim = QLSim(def: shift(harbor: quay,
                                   arrivals: [QLArrival(tick: 1, ship: ship(length: 2, draft: 3))]),
                        upgrades: .zero)
        sim.advance()
        expectEqual(sim.canBerth(shipID: 1, atSlot: 2), .tooLong, "length must fit the quay")
        expectEqual(sim.canBerth(shipID: 1, atSlot: 1), .tooShallow, "draft 3 cannot use a depth-2 slot")
        expectEqual(sim.canBerth(shipID: 1, atSlot: 0), .none, "a legal berth is accepted")
    }

    static func testChannelIsExclusive() {
        let quay = harbour(slots: Array(repeating: QLSlot(depth: 5, equipment: .crane), count: 6),
                           channel: 20)
        var sim = QLSim(def: shift(harbor: quay, arrivals: [
            QLArrival(tick: 1, ship: ship(id: 1)),
            QLArrival(tick: 1, ship: ship(id: 2)),
        ]), upgrades: .zero)
        sim.advance()
        expectEqual(sim.berth(shipID: 1, atSlot: 0), .none, "first ship enters")
        expectEqual(sim.canBerth(shipID: 2, atSlot: 2), .channelBusy, "channel admits one ship at a time")
        for _ in 0..<20 { sim.advance() }
        expectEqual(sim.canBerth(shipID: 2, atSlot: 2), .none, "channel frees when the transit ends")
    }

    static func testTideTriangleWave() {
        let quay = harbour(slots: [QLSlot(depth: 3, equipment: .crane)],
                           amplitude: 1, step: 10)
        let sim = QLSim(def: shift(harbor: quay, arrivals: []), upgrades: .zero)
        expectEqual(sim.tideOffset(at: 0), -1, "cycle starts at low water")
        expectEqual(sim.tideOffset(at: 10), 0, "one step up after one step of ticks")
        expectEqual(sim.tideOffset(at: 20), 1, "high water at the top of the ramp")
        expectEqual(sim.tideOffset(at: 30), 0, "and back down")
        expectEqual(sim.tideOffset(at: 40), -1, "full cycle is 4 steps at amplitude 1")
        expectEqual(sim.tideOffset(at: 41), -1, "cycle repeats")
    }

    static func testGroundingHoldsTheBerth() {
        let quay = harbour(slots: [QLSlot(depth: 3, equipment: .crane),
                                   QLSlot(depth: 3, equipment: .crane)],
                           channel: 1, amplitude: 1, step: 10)
        // Draft 4 over depth 3 can only enter at high water.
        var sim = QLSim(def: shift(harbor: quay, arrivals: [
            QLArrival(tick: 1, ship: ship(length: 2, draft: 4, tons: 1)),
        ]), upgrades: .zero)
        while sim.tick < 20 { sim.advance() }
        expectEqual(sim.berth(shipID: 1, atSlot: 0), .none, "enters on the tide")
        while sim.tick < 32 { sim.advance() }
        expectEqual(sim.ships[0].state, .aground, "falling water grounds the hull")
        expect(!sim.depart(shipID: 1), "an aground ship cannot leave")
        expect(sim.counters.groundings >= 1, "grounding is counted for the gate")
        expect(sim.ships[0].slots != nil, "an aground ship still holds its berths")
    }

    static func testMismatchedGearCostsMore() {
        let matched = harbour(slots: [QLSlot(depth: 5, equipment: .crane),
                                      QLSlot(depth: 5, equipment: .crane)], channel: 1)
        let wrong = harbour(slots: [QLSlot(depth: 5, equipment: .pipeline),
                                    QLSlot(depth: 5, equipment: .pipeline)], channel: 1)
        func unloadTicks(_ quay: QLHarborDef) -> Int {
            var sim = QLSim(def: shift(harbor: quay, arrivals: [
                QLArrival(tick: 1, ship: ship(cargo: .container, tons: 4)),
            ]), upgrades: .zero)
            sim.advance()
            _ = sim.berth(shipID: 1, atSlot: 0)
            var t = 0
            while sim.ships[0].unloadLeft > 0 && t < 10_000 { sim.advance(); t += 1 }
            return t
        }
        let fast = unloadTicks(matched), slow = unloadTicks(wrong)
        expect(slow > fast * 2, "wrong gear costs x2.5: \(slow) vs \(fast)")
    }

    static func testPatienceOnlyBurnsWhileWaiting() {
        let quay = harbour(slots: [QLSlot(depth: 5, equipment: .crane),
                                   QLSlot(depth: 5, equipment: .crane)], channel: 40)
        var sim = QLSim(def: shift(harbor: quay, arrivals: [
            QLArrival(tick: 1, ship: ship(patience: 200)),
        ]), upgrades: .zero)
        sim.advance()
        for _ in 0..<10 { sim.advance() }
        expect(sim.ships[0].patienceLeft < 200, "patience burns on the roadstead")
        _ = sim.berth(shipID: 1, atSlot: 0)
        let atBerthing = sim.ships[0].patienceLeft
        for _ in 0..<30 { sim.advance() }
        expectEqual(sim.ships[0].patienceLeft, atBerthing, "patience freezes once under way")
    }

    static func testRoadsteadOverflowLosesShip() {
        let quay = harbour(slots: [QLSlot(depth: 5, equipment: .crane),
                                   QLSlot(depth: 5, equipment: .crane)], roadstead: 2)
        var sim = QLSim(def: shift(harbor: quay, arrivals: [
            QLArrival(tick: 1, ship: ship(id: 1)),
            QLArrival(tick: 1, ship: ship(id: 2)),
            QLArrival(tick: 1, ship: ship(id: 3)),
        ]), upgrades: .zero)
        sim.advance()
        expectEqual(sim.waitingShips.count, 2, "roadstead holds its capacity")
        expectEqual(sim.ships.first(where: { $0.id == 3 })?.state, QLShipState.lost,
                    "the overflow ship is lost")
        expectEqual(sim.reputation, QLTuning.baseReputation - 1, "and costs reputation")
    }

    static func testSlotsFreeAtStartOfDeparture() {
        let quay = harbour(slots: Array(repeating: QLSlot(depth: 5, equipment: .crane), count: 4),
                           channel: 20)
        var sim = QLSim(def: shift(harbor: quay, arrivals: [
            QLArrival(tick: 1, ship: ship(id: 1, tons: 1)),
        ]), upgrades: .zero)
        sim.advance()
        _ = sim.berth(shipID: 1, atSlot: 0)
        while sim.ships[0].state == .transitingIn { sim.advance() }
        while sim.ships[0].unloadLeft > 0 { sim.advance() }
        expect(sim.depart(shipID: 1), "a finished ship departs")
        expectEqual(sim.ships[0].state, .transitingOut, "and is under way")
        expect(sim.occupiedSlots.isEmpty, "its berths are free the moment it pulls out")
    }

    static func testUpgradesApply() {
        let quay = harbour(slots: [QLSlot(depth: 1, equipment: .crane),
                                   QLSlot(depth: 1, equipment: .crane)], channel: 100)
        var plain = QLSim(def: shift(harbor: quay,
                                     arrivals: [QLArrival(tick: 1, ship: ship(draft: 2))]),
                          upgrades: .zero)
        plain.advance()
        expectEqual(plain.canBerth(shipID: 1, atSlot: 0), .tooShallow,
                    "draft 2 over depth 1 is refused")

        var dredged = QLSim(def: shift(harbor: quay,
                                       arrivals: [QLArrival(tick: 1, ship: ship(draft: 2))]),
                            upgrades: QLUpgradeLevels(cranes: 0, tugs: 0, dredge: 1,
                                                      roadstead: 0, crew: 0))
        dredged.advance()
        expectEqual(dredged.canBerth(shipID: 1, atSlot: 0), .none,
                    "dredging one level admits it")

        let crewed = QLSim(def: shift(harbor: quay, arrivals: []),
                           upgrades: QLUpgradeLevels(cranes: 0, tugs: 0, dredge: 0,
                                                     roadstead: 0, crew: 2))
        expectEqual(crewed.reputation, QLTuning.baseReputation + 2,
                    "crew raises starting reputation")
    }

    static func testDeterminism() {
        let quay = harbour(slots: Array(repeating: QLSlot(depth: 4, equipment: .crane), count: 6),
                           channel: 15, amplitude: 1, step: 12)
        let arrivals = (1...6).map { QLArrival(tick: $0 * 7, ship: ship(id: $0, tons: 3)) }
        func replay() -> [Int] {
            var sim = QLSim(def: shift(harbor: quay, arrivals: arrivals), upgrades: .zero)
            var trace: [Int] = []
            for _ in 0..<400 {
                sim.advance()
                if let w = sim.waitingShips.first, !sim.channelBusy {
                    _ = sim.berth(shipID: w.id, atSlot: 0)
                }
                for s in sim.ships where s.state == .berthed && s.unloadLeft <= 0 {
                    _ = sim.depart(shipID: s.id)
                }
                trace.append(sim.counters.tonsServed)
            }
            return trace
        }
        expectEqual(replay(), replay(), "the same inputs must produce the same trace")
    }
}
