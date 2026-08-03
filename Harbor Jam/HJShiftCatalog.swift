import Foundation

/// Every balance number in the game. The tuning loop that has to satisfy the
/// acceptance gate edits this enum and `HJCatalog.ports`, and nothing else — a
/// magic number anywhere else in the codebase is a bug, because it would be a
/// lever the gate cannot see.
enum HJTuning {
    static let tickHz = 20

    /// Work units per ton, in doubled units (see `HJShip.unloadLeft`).
    static func workPerTon(_ cargo: HJCargo) -> Int {
        switch cargo {
        case .container: return 6
        case .bulk: return 8
        case .liquid: return 5
        }
    }

    /// Coins per ton.
    static func rate(_ cargo: HJCargo) -> Int {
        switch cargo {
        case .container: return 10
        case .bulk: return 8
        case .liquid: return 12
        }
    }

    static let vipRateMultiplier = 3
    static let speedRate = 2            // score per tick saved against par
    static let baseReputation = 3
    static let target3Percent = 92      // of policy S's score
    static let target2Percent = 70

    static let unloadDiscountPerCraneLevel = 8    // percent
    static let transitDiscountPerTugLevel = 10    // percent
    static let longShipLength = 4                 // transit ×1.5 in ports that penalise it
    static let patiencePerTick = 2
    static let patiencePerTickInStorm = 3
}

struct HJPortTemplate {
    var index: Int              // 1...7
    var name: String
    var tagline: String
    var slotCount: Int
    var depthRange: ClosedRange<Int>
    var equipment: [HJEquipment]     // pool drawn from when laying out a quay
    var cargoes: [HJCargo]
    var channelTransitTicks: Int
    var tideAmplitude: Int
    var tideStepTicks: Int
    var shipLengths: ClosedRange<Int>
    var draftRange: ClosedRange<Int>
    var shipCount: ClosedRange<Int>
    var usesOutages: Bool
    var usesStorms: Bool
    var usesVIP: Bool
    var longShipTransitPenalty: Bool
}

enum HJCatalog {
    static let shiftsPerPort = 12
    static var portCount: Int { ports.count }
    static var totalShifts: Int { portCount * shiftsPerPort }

    /// Port `n` opens at 20·(n−1) stars, out of 36 available per port.
    static func starsToUnlock(port: Int) -> Int { max(0, 20 * (port - 1)) }

    static func template(port: Int) -> HJPortTemplate? {
        ports.first { $0.index == port }
    }

    /// Each port introduces exactly one new thing and nothing else. The order is
    /// the teaching order: a mechanic the player has not met cannot be what
    /// beats them.
    static let ports: [HJPortTemplate] = [
        HJPortTemplate(index: 1, name: "Quiet Cove", tagline: "Learn the quay",
                       slotCount: 8, depthRange: 5...5, equipment: [.crane],
                       cargoes: [.container], channelTransitTicks: 30,
                       tideAmplitude: 0, tideStepTicks: 0,
                       shipLengths: 2...3, draftRange: 1...3, shipCount: 12...16,
                       usesOutages: false, usesStorms: false, usesVIP: false,
                       longShipTransitPenalty: false),
        HJPortTemplate(index: 2, name: "Tidewater Quay", tagline: "Mind the water line",
                       slotCount: 9, depthRange: 2...5, equipment: [.crane],
                       cargoes: [.container], channelTransitTicks: 30,
                       tideAmplitude: 1, tideStepTicks: 100,
                       shipLengths: 2...4, draftRange: 1...4, shipCount: 14...18,
                       usesOutages: false, usesStorms: false, usesVIP: false,
                       longShipTransitPenalty: false),
        HJPortTemplate(index: 3, name: "Narrow Channel", tagline: "One way in",
                       slotCount: 9, depthRange: 2...5, equipment: [.crane],
                       cargoes: [.container], channelTransitTicks: 80,
                       tideAmplitude: 1, tideStepTicks: 100,
                       shipLengths: 2...4, draftRange: 1...4, shipCount: 16...20,
                       usesOutages: false, usesStorms: false, usesVIP: false,
                       longShipTransitPenalty: false),
        HJPortTemplate(index: 4, name: "Mixed Berths", tagline: "Right gear, right berth",
                       slotCount: 10, depthRange: 2...5,
                       equipment: [.crane, .conveyor, .pipeline, .none],
                       cargoes: [.container, .bulk, .liquid], channelTransitTicks: 80,
                       tideAmplitude: 1, tideStepTicks: 100,
                       shipLengths: 2...4, draftRange: 1...4, shipCount: 16...22,
                       usesOutages: false, usesStorms: false, usesVIP: false,
                       longShipTransitPenalty: false),
        HJPortTemplate(index: 5, name: "Storm Roads", tagline: "Weather and repairs",
                       slotCount: 10, depthRange: 2...5,
                       equipment: [.crane, .conveyor, .pipeline, .none],
                       cargoes: [.container, .bulk, .liquid], channelTransitTicks: 80,
                       tideAmplitude: 1, tideStepTicks: 100,
                       shipLengths: 2...4, draftRange: 1...4, shipCount: 18...24,
                       usesOutages: true, usesStorms: true, usesVIP: false,
                       longShipTransitPenalty: false),
        HJPortTemplate(index: 6, name: "Deepwater Port", tagline: "Big hulls, deep water",
                       slotCount: 12, depthRange: 2...5,
                       equipment: [.crane, .conveyor, .pipeline, .none],
                       cargoes: [.container, .bulk, .liquid], channelTransitTicks: 80,
                       tideAmplitude: 2, tideStepTicks: 90,
                       shipLengths: 3...5, draftRange: 2...5, shipCount: 20...26,
                       usesOutages: true, usesStorms: true, usesVIP: false,
                       longShipTransitPenalty: true),
        HJPortTemplate(index: 7, name: "Grand Harbor", tagline: "Everything at once",
                       slotCount: 12, depthRange: 2...5,
                       equipment: [.crane, .conveyor, .pipeline, .none],
                       cargoes: [.container, .bulk, .liquid], channelTransitTicks: 80,
                       tideAmplitude: 2, tideStepTicks: 90,
                       shipLengths: 2...5, draftRange: 1...5, shipCount: 22...28,
                       usesOutages: true, usesStorms: true, usesVIP: true,
                       longShipTransitPenalty: true),
    ]
}
