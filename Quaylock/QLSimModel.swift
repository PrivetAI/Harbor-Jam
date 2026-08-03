import Foundation

/// Cargo and berth gear pair strictly one-to-one: a berth either has the gear a
/// hull needs or it does not, and "nearly right" is not a case. Two outcomes are
/// something a player can read off the quay at a glance; a matrix of partial
/// matches is not.
enum QLCargo: Int, Codable, CaseIterable {
    case container = 0, bulk = 1, liquid = 2

    var equipment: QLEquipment {
        switch self {
        case .container: return .crane
        case .bulk: return .conveyor
        case .liquid: return .pipeline
        }
    }

    var shortName: String {
        switch self {
        case .container: return "Containers"
        case .bulk: return "Bulk"
        case .liquid: return "Liquid"
        }
    }
}

enum QLEquipment: Int, Codable, CaseIterable {
    case none = 0, crane = 1, conveyor = 2, pipeline = 3
}

struct QLSlot: Codable, Equatable {
    var depth: Int              // 1...5, before tide and dredging
    var equipment: QLEquipment
}

enum QLShipState: Int, Codable {
    case waiting = 0, transitingIn = 1, berthed = 2, aground = 3
    case transitingOut = 4, served = 5, lost = 6
}

struct QLShip: Codable, Equatable, Identifiable {
    var id: Int
    var length: Int             // 2...5 slots
    var draft: Int              // 1...5
    var cargo: QLCargo
    var tons: Int
    /// Stored DOUBLED. Patience burns 2 units per tick normally and 3 during a
    /// storm, which is how the ×1.5 storm multiplier stays in integer maths —
    /// the whole simulation has to replay identically in the headless harness,
    /// and floating point would not.
    var patienceTicks: Int
    var isVIP: Bool

    var state: QLShipState = .waiting
    var patienceLeft: Int = 0
    var berthStart: Int? = nil  // index of the first occupied slot
    /// Stored DOUBLED, same reason. Unload burns 2 units per tick; matching gear
    /// costs 2 units of work per ton and wrong gear costs 5, i.e. the ×2.5.
    var unloadLeft: Int = 0
    var transitLeft: Int = 0

    var slots: Range<Int>? {
        guard let s = berthStart else { return nil }
        return s..<(s + length)
    }

    /// A hull under way inbound already owns her berths — otherwise a second
    /// ship could be sent to the same stretch of quay while the first is still
    /// in the channel.
    var holdsBerth: Bool {
        state == .berthed || state == .aground || state == .transitingIn
    }
}

struct QLHarborDef: Codable, Equatable {
    var slots: [QLSlot]
    var channelTransitTicks: Int
    var tideAmplitude: Int      // 0, 1 or 2
    var tideStepTicks: Int
    var roadsteadCapacity: Int
}

struct QLArrival: Codable, Equatable {
    var tick: Int
    var ship: QLShip
}

struct QLSlotOutage: Codable, Equatable {
    var slot: Int
    var startTick: Int
    var endTick: Int
}

struct QLStormWindow: Codable, Equatable {
    var startTick: Int
    var endTick: Int
}

struct QLShiftDef: Codable, Equatable {
    var port: Int               // 1...7
    var shift: Int              // 1...12
    var harbor: QLHarborDef
    var arrivals: [QLArrival]
    var outages: [QLSlotOutage]
    var storms: [QLStormWindow]
    var parTicks: Int           // baked by HarborForge from policy S
    var target2: Int
    var target3: Int
}

struct QLUpgradeLevels: Codable, Equatable {
    var cranes: Int = 0         // 0...5, -8 % unload each
    var tugs: Int = 0           // 0...3, -10 % channel transit each
    var dredge: Int = 0         // 0...2, +1 depth on every slot each
    var roadstead: Int = 0      // 0...2, +1 waiting berth each
    var crew: Int = 0           // 0...2, +1 starting reputation each

    static let zero = QLUpgradeLevels()
}

/// Why a berth command was refused. The board draws each of these differently;
/// collapsing them into one generic shake is what made the previous version of
/// this game feel arbitrary rather than hard.
enum QLBerthRefusal: Int, Equatable {
    case none = 0, tooLong, occupied, tooShallow, channelBusy, notWaiting, outage
}

/// Proof that each advertised mechanic actually fired. The acceptance gate reads
/// these: four of the five mechanics in the previous game were provably inert,
/// and nobody noticed until something counted them.
struct QLSimCounters: Codable, Equatable {
    var groundings: Int = 0
    /// Commands refused because the channel was occupied. Counts player mistakes
    /// only — a policy checks before it acts, so this stays 0 in the harness and
    /// cannot be used to prove the channel matters.
    var channelRefusals: Int = 0
    /// Ticks the channel spent occupied. This is the honest measure of the
    /// channel being a contended resource, and it is what the gate reads.
    var channelBusyTicks: Int = 0
    var mismatchedUnloads: Int = 0
    var shipsServed: Int = 0
    var shipsLost: Int = 0
    var tonsServed: Int = 0
    var revenue: Int = 0
}
