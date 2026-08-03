import Foundation
import SwiftUI

struct QLShiftRecord: Codable, Equatable {
    var stars: Int
    var bestScore: Int

    init(stars: Int, bestScore: Int) {
        self.stars = stars
        self.bestScore = bestScore
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stars = try c.decodeIfPresent(Int.self, forKey: .stars) ?? 0
        bestScore = try c.decodeIfPresent(Int.self, forKey: .bestScore) ?? 0
    }
}

/// Upgrade lines. `rawValue` is the persisted dictionary key — renaming a case
/// after release silently resets that line for everyone who has it.
enum QLUpgradeLine: String, CaseIterable, Identifiable {
    case cranes, tugs, dredge, roadstead, crew
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cranes: return "Cranes"
        case .tugs: return "Tugs"
        case .dredge: return "Dredging"
        case .roadstead: return "Roadstead"
        case .crew: return "Crew"
        }
    }

    var detail: String {
        switch self {
        case .cranes: return "Unload 8% faster per level"
        case .tugs: return "Channel transit 10% shorter per level"
        case .dredge: return "Every berth one fathom deeper per level"
        case .roadstead: return "One more ship may wait per level"
        case .crew: return "Start each shift with one more reputation"
        }
    }

    var maxLevel: Int {
        switch self {
        case .cranes: return 5
        case .tugs: return 3
        default: return 2
        }
    }

    func cost(atLevel level: Int) -> Int { 400 * (level + 1) * (level + 1) }
}

struct QLStats: Codable, Equatable {
    var shiftsCleared = 0
    var tonsServed = 0
    var shipsServed = 0
    var shipsLost = 0
    var groundings = 0
    var flawlessShifts = 0        // cleared without losing a ship
    var noGroundingShifts = 0

    init() {}

    /// Every field via `decodeIfPresent`. A non-optional field added later makes
    /// the synthesized decoder throw on the missing key and wipes all progress —
    /// this has already happened once in this portfolio.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shiftsCleared = try c.decodeIfPresent(Int.self, forKey: .shiftsCleared) ?? 0
        tonsServed = try c.decodeIfPresent(Int.self, forKey: .tonsServed) ?? 0
        shipsServed = try c.decodeIfPresent(Int.self, forKey: .shipsServed) ?? 0
        shipsLost = try c.decodeIfPresent(Int.self, forKey: .shipsLost) ?? 0
        groundings = try c.decodeIfPresent(Int.self, forKey: .groundings) ?? 0
        flawlessShifts = try c.decodeIfPresent(Int.self, forKey: .flawlessShifts) ?? 0
        noGroundingShifts = try c.decodeIfPresent(Int.self, forKey: .noGroundingShifts) ?? 0
    }
}

struct QLSaveState: Codable, Equatable {
    var shiftRecords: [String: QLShiftRecord] = [:]   // "port-shift"
    var coins = 0
    var upgrades: [String: Int] = [:]
    var watchBestTons = 0
    var unlockedAchievements: [String] = []
    var stats = QLStats()
    var soundOn = true
    var hapticsOn = true
    var onboardingSeen = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shiftRecords = try c.decodeIfPresent([String: QLShiftRecord].self, forKey: .shiftRecords) ?? [:]
        coins = try c.decodeIfPresent(Int.self, forKey: .coins) ?? 0
        unlockedAchievements = try c.decodeIfPresent([String].self, forKey: .unlockedAchievements) ?? []
        upgrades = try c.decodeIfPresent([String: Int].self, forKey: .upgrades) ?? [:]
        watchBestTons = try c.decodeIfPresent(Int.self, forKey: .watchBestTons) ?? 0
        stats = try c.decodeIfPresent(QLStats.self, forKey: .stats) ?? QLStats()
        soundOn = try c.decodeIfPresent(Bool.self, forKey: .soundOn) ?? true
        hapticsOn = try c.decodeIfPresent(Bool.self, forKey: .hapticsOn) ?? true
        onboardingSeen = try c.decodeIfPresent(Bool.self, forKey: .onboardingSeen) ?? false
    }
}

struct QLAchievement: Identifiable {
    var id: String
    var title: String
    var detail: String
    var check: (QLSaveState) -> Bool
}

enum QLAchievements {
    static func totalStars(_ save: QLSaveState) -> Int {
        save.shiftRecords.values.reduce(0) { $0 + $1.stars }
    }

    static func portStars(_ save: QLSaveState, port: Int) -> Int {
        (1...QLCatalog.shiftsPerPort).reduce(0) {
            $0 + (save.shiftRecords["\(port)-\($1)"]?.stars ?? 0)
        }
    }

    static let all: [QLAchievement] = [
        QLAchievement(id: "first_shift", title: "First Watch",
                      detail: "Clear your first shift") { $0.stats.shiftsCleared >= 1 },
        QLAchievement(id: "shifts_10", title: "Harbourmaster's Nod",
                      detail: "Clear 10 shifts") { $0.stats.shiftsCleared >= 10 },
        QLAchievement(id: "shifts_40", title: "Old Hand",
                      detail: "Clear 40 shifts") { $0.stats.shiftsCleared >= 40 },
        QLAchievement(id: "shifts_84", title: "Every Berth Worked",
                      detail: "Clear all 84 shifts") { save in
            (1...QLCatalog.portCount).allSatisfy { p in
                (1...QLCatalog.shiftsPerPort).allSatisfy {
                    (save.shiftRecords["\(p)-\($0)"]?.stars ?? 0) >= 1
                }
            }
        },
        QLAchievement(id: "tons_1k", title: "First Thousand",
                      detail: "Move 1,000 tons") { $0.stats.tonsServed >= 1_000 },
        QLAchievement(id: "tons_25k", title: "Deep Water Trade",
                      detail: "Move 25,000 tons") { $0.stats.tonsServed >= 25_000 },
        QLAchievement(id: "tons_200k", title: "Port of Record",
                      detail: "Move 200,000 tons") { $0.stats.tonsServed >= 200_000 },
        QLAchievement(id: "stars_25", title: "Gold on the Water",
                      detail: "Collect 25 stars") { totalStars($0) >= 25 },
        QLAchievement(id: "stars_80", title: "Star Charter",
                      detail: "Collect 80 stars") { totalStars($0) >= 80 },
        QLAchievement(id: "stars_150", title: "Constellation Pilot",
                      detail: "Collect 150 stars") { totalStars($0) >= 150 },
        QLAchievement(id: "port1_perfect", title: "Cove Perfectionist",
                      detail: "All 36 stars in Quiet Cove") { portStars($0, port: 1) >= 36 },
        QLAchievement(id: "port2_perfect", title: "Reads the Water",
                      detail: "All 36 stars in Tidewater Quay") { portStars($0, port: 2) >= 36 },
        QLAchievement(id: "port3_perfect", title: "Channel Discipline",
                      detail: "All 36 stars in Narrow Channel") { portStars($0, port: 3) >= 36 },
        QLAchievement(id: "flawless_10", title: "Nobody Turned Away",
                      detail: "Clear 10 shifts without losing a ship") { $0.stats.flawlessShifts >= 10 },
        QLAchievement(id: "nogrounding_20", title: "Never Touched Bottom",
                      detail: "Clear 20 shifts without a grounding") { $0.stats.noGroundingShifts >= 20 },
        QLAchievement(id: "ships_250", title: "Two Fifty Alongside",
                      detail: "Berth and clear 250 ships") { $0.stats.shipsServed >= 250 },
        QLAchievement(id: "upgrades_max", title: "Fully Fitted",
                      detail: "Max out every upgrade line") { save in
            QLUpgradeLine.allCases.allSatisfy { (save.upgrades[$0.rawValue] ?? 0) >= $0.maxLevel }
        },
        QLAchievement(id: "watch_500", title: "Standing Watch",
                      detail: "Move 500 tons in one Watch run") { $0.watchBestTons >= 500 },
        QLAchievement(id: "watch_2000", title: "Long Watch",
                      detail: "Move 2,000 tons in one Watch run") { $0.watchBestTons >= 2_000 },
        QLAchievement(id: "all_ports", title: "Seven Harbours",
                      detail: "Unlock every port") { totalStars($0) >= QLCatalog.starsToUnlock(port: QLCatalog.portCount) },
    ]
}

final class QLStore: ObservableObject {
    /// v3: the dispatcher. v1 was the sliding-block game and is not migrated —
    /// `par` meant something else, so every star earned under it is meaningless.
    /// The app was never released, so nothing real is lost.
    static let saveKey = "ql.state.v1"

    @Published var save: QLSaveState
    @Published var recentlyUnlocked: [String] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: QLStore.saveKey),
           let decoded = try? JSONDecoder().decode(QLSaveState.self, from: data) {
            save = decoded
        } else {
            save = QLSaveState()
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(save) {
            UserDefaults.standard.set(data, forKey: QLStore.saveKey)
        }
    }

    func resetProgress() {
        UserDefaults.standard.removeObject(forKey: QLStore.saveKey)
        save = QLSaveState()
        recentlyUnlocked = []
        persist()
    }

    func refreshAchievements() {
        for a in QLAchievements.all where !save.unlockedAchievements.contains(a.id) {
            if a.check(save) {
                save.unlockedAchievements.append(a.id)
                recentlyUnlocked.append(a.id)
            }
        }
    }

    // MARK: - Upgrades

    func upgradeLevel(_ line: QLUpgradeLine) -> Int { save.upgrades[line.rawValue] ?? 0 }

    func upgradeLevels() -> QLUpgradeLevels {
        QLUpgradeLevels(cranes: upgradeLevel(.cranes),
                        tugs: upgradeLevel(.tugs),
                        dredge: upgradeLevel(.dredge),
                        roadstead: upgradeLevel(.roadstead),
                        crew: upgradeLevel(.crew))
    }

    @discardableResult
    func buyUpgrade(_ line: QLUpgradeLine) -> Bool {
        let level = upgradeLevel(line)
        guard level < line.maxLevel else { return false }
        let cost = line.cost(atLevel: level)
        guard save.coins >= cost else { return false }
        save.coins -= cost
        save.upgrades[line.rawValue] = level + 1
        refreshAchievements()
        persist()
        return true
    }

    // MARK: - Progression

    func record(port: Int, shift: Int) -> QLShiftRecord? { save.shiftRecords["\(port)-\(shift)"] }

    func totalStars() -> Int { QLAchievements.totalStars(save) }

    func portStars(_ port: Int) -> Int { QLAchievements.portStars(save, port: port) }

    func isPortUnlocked(_ port: Int) -> Bool {
        totalStars() >= QLCatalog.starsToUnlock(port: port)
    }

    func isShiftUnlocked(port: Int, shift: Int) -> Bool {
        guard isPortUnlocked(port) else { return false }
        if shift == 1 { return true }
        return (record(port: port, shift: shift - 1)?.stars ?? 0) >= 1
    }

    /// Records a cleared shift and returns the stars earned. Coins are credited
    /// every time; the record itself only ever improves.
    @discardableResult
    func reportShiftWin(port: Int, shift: Int, score: Int, stars: Int,
                        counters: QLSimCounters) -> Int {
        let key = "\(port)-\(shift)"
        let old = save.shiftRecords[key]
        save.shiftRecords[key] = QLShiftRecord(stars: max(stars, old?.stars ?? 0),
                                               bestScore: max(score, old?.bestScore ?? 0))
        save.coins += counters.revenue
        save.stats.shiftsCleared += 1
        save.stats.tonsServed += counters.tonsServed
        save.stats.shipsServed += counters.shipsServed
        save.stats.shipsLost += counters.shipsLost
        save.stats.groundings += counters.groundings
        if counters.shipsLost == 0 { save.stats.flawlessShifts += 1 }
        if counters.groundings == 0 { save.stats.noGroundingShifts += 1 }
        refreshAchievements()
        persist()
        return stars
    }

    func reportWatchRun(tons: Int) {
        save.watchBestTons = max(save.watchBestTons, tons)
        save.stats.tonsServed += tons
        refreshAchievements()
        persist()
    }
}
