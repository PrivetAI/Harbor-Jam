import Foundation
import SwiftUI

struct HJLevelRecord: Codable, Equatable {
    var stars: Int
    var bestTaps: Int

    init(stars: Int, bestTaps: Int) {
        self.stars = stars
        self.bestTaps = bestTaps
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stars = try c.decodeIfPresent(Int.self, forKey: .stars) ?? 0
        bestTaps = try c.decodeIfPresent(Int.self, forKey: .bestTaps) ?? 0
    }
}

struct HJStats: Codable, Equatable {
    var levelsCleared: Int
    var totalTaps: Int
    var totalUndos: Int
    var boatsExited: Int
    var tugsUsed: Int
    var dailiesCompleted: Int
    var winsWithoutUndo: Int

    init() {
        levelsCleared = 0; totalTaps = 0; totalUndos = 0
        boatsExited = 0; tugsUsed = 0; dailiesCompleted = 0; winsWithoutUndo = 0
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        levelsCleared = try c.decodeIfPresent(Int.self, forKey: .levelsCleared) ?? 0
        totalTaps = try c.decodeIfPresent(Int.self, forKey: .totalTaps) ?? 0
        totalUndos = try c.decodeIfPresent(Int.self, forKey: .totalUndos) ?? 0
        boatsExited = try c.decodeIfPresent(Int.self, forKey: .boatsExited) ?? 0
        tugsUsed = try c.decodeIfPresent(Int.self, forKey: .tugsUsed) ?? 0
        dailiesCompleted = try c.decodeIfPresent(Int.self, forKey: .dailiesCompleted) ?? 0
        winsWithoutUndo = try c.decodeIfPresent(Int.self, forKey: .winsWithoutUndo) ?? 0
    }
}

struct HJSaveState: Codable, Equatable {
    var records: [String: HJLevelRecord]      // "chapter-level" -> record
    var unlockedAchievements: [String]
    var stats: HJStats
    var dailyStreak: Int
    var lastDailyDayKey: Int
    var bestDailyTaps: [String: Int]          // dayKey string -> taps
    var soundOn: Bool
    var hapticsOn: Bool
    var colorblindPatterns: Bool
    var onboardingSeen: Bool

    init() {
        records = [:]
        unlockedAchievements = []
        stats = HJStats()
        dailyStreak = 0
        lastDailyDayKey = 0
        bestDailyTaps = [:]
        soundOn = true
        hapticsOn = true
        colorblindPatterns = false
        onboardingSeen = false
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = try c.decodeIfPresent([String: HJLevelRecord].self, forKey: .records) ?? [:]
        unlockedAchievements = try c.decodeIfPresent([String].self, forKey: .unlockedAchievements) ?? []
        stats = try c.decodeIfPresent(HJStats.self, forKey: .stats) ?? HJStats()
        dailyStreak = try c.decodeIfPresent(Int.self, forKey: .dailyStreak) ?? 0
        lastDailyDayKey = try c.decodeIfPresent(Int.self, forKey: .lastDailyDayKey) ?? 0
        bestDailyTaps = try c.decodeIfPresent([String: Int].self, forKey: .bestDailyTaps) ?? [:]
        soundOn = try c.decodeIfPresent(Bool.self, forKey: .soundOn) ?? true
        hapticsOn = try c.decodeIfPresent(Bool.self, forKey: .hapticsOn) ?? true
        colorblindPatterns = try c.decodeIfPresent(Bool.self, forKey: .colorblindPatterns) ?? false
        onboardingSeen = try c.decodeIfPresent(Bool.self, forKey: .onboardingSeen) ?? false
    }
}

struct HJAchievement: Identifiable {
    var id: String
    var title: String
    var detail: String
    var check: (HJSaveState) -> Bool
}

enum HJAchievements {
    static func chapterStars(_ save: HJSaveState, chapter: Int) -> Int {
        var total = 0
        for lvl in 0..<HJCatalog.levelsPerChapter {
            total += save.records["\(chapter)-\(lvl)"]?.stars ?? 0
        }
        return total
    }
    static func totalStars(_ save: HJSaveState) -> Int {
        save.records.values.reduce(0) { $0 + $1.stars }
    }

    static let all: [HJAchievement] = [
        HJAchievement(id: "first_exit", title: "Maiden Voyage", detail: "Sail your first boat out of the harbor") { $0.stats.boatsExited >= 1 },
        HJAchievement(id: "first_clear", title: "Harbormaster's Nod", detail: "Clear your first level") { $0.stats.levelsCleared >= 1 },
        HJAchievement(id: "boats_100", title: "Century Fleet", detail: "Exit 100 boats") { $0.stats.boatsExited >= 100 },
        HJAchievement(id: "boats_500", title: "Grand Flotilla", detail: "Exit 500 boats") { $0.stats.boatsExited >= 500 },
        HJAchievement(id: "boats_1500", title: "Endless Wake", detail: "Exit 1,500 boats") { $0.stats.boatsExited >= 1500 },
        HJAchievement(id: "clears_20", title: "Busy Docks", detail: "Clear 20 levels") { $0.stats.levelsCleared >= 20 },
        HJAchievement(id: "clears_70", title: "Chart Keeper", detail: "Clear 70 levels") { $0.stats.levelsCleared >= 70 },
        HJAchievement(id: "clears_140", title: "Every Berth Empty", detail: "Clear all 140 campaign levels") { save in
            (0..<HJCatalog.chapters.count).allSatisfy { ch in
                (0..<HJCatalog.levelsPerChapter).allSatisfy { (save.records["\(ch)-\($0)"]?.stars ?? 0) >= 1 }
            }
        },
        HJAchievement(id: "stars_50", title: "Gold on the Water", detail: "Collect 50 stars") { totalStars($0) >= 50 },
        HJAchievement(id: "stars_180", title: "Star Charter", detail: "Collect 180 stars") { totalStars($0) >= 180 },
        HJAchievement(id: "stars_300", title: "Constellation Pilot", detail: "Collect 300 stars") { totalStars($0) >= 300 },
        HJAchievement(id: "ch0_perfect", title: "Cove Perfectionist", detail: "Earn all 60 stars in Quiet Cove") { chapterStars($0, chapter: 0) >= 60 },
        HJAchievement(id: "ch1_perfect", title: "Current Whisperer", detail: "Earn all 60 stars in Fisher Wharf") { chapterStars($0, chapter: 1) >= 60 },
        HJAchievement(id: "ch2_perfect", title: "Ferry Scheduler", detail: "Earn all 60 stars in Ferry Port") { chapterStars($0, chapter: 2) >= 60 },
        HJAchievement(id: "no_undo_10", title: "Steady Hand", detail: "Win 10 levels without using undo") { $0.stats.winsWithoutUndo >= 10 },
        HJAchievement(id: "no_undo_40", title: "Iron Compass", detail: "Win 40 levels without using undo") { $0.stats.winsWithoutUndo >= 40 },
        HJAchievement(id: "daily_1", title: "Morning Round", detail: "Complete a Daily Jam") { $0.stats.dailiesCompleted >= 1 },
        HJAchievement(id: "daily_streak_7", title: "Seven Tides", detail: "Reach a 7-day Daily streak") { $0.dailyStreak >= 7 },
        HJAchievement(id: "tugs_15", title: "Tug Captain", detail: "Use the tug 15 times") { $0.stats.tugsUsed >= 15 },
        HJAchievement(id: "taps_2000", title: "Thousand Horns", detail: "Make 2,000 moves") { $0.stats.totalTaps >= 2000 },
    ]
}

final class HJStore: ObservableObject {
    static let saveKey = "hbj.state.v1"

    @Published var save: HJSaveState
    @Published var recentlyUnlocked: [String] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: HJStore.saveKey),
           let decoded = try? JSONDecoder().decode(HJSaveState.self, from: data) {
            save = decoded
        } else {
            save = HJSaveState()
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(save) {
            UserDefaults.standard.set(data, forKey: HJStore.saveKey)
        }
    }

    func resetProgress() {
        UserDefaults.standard.removeObject(forKey: HJStore.saveKey)
        save = HJSaveState()
        recentlyUnlocked = []
        persist()
    }

    func refreshAchievements() {
        for a in HJAchievements.all where !save.unlockedAchievements.contains(a.id) {
            if a.check(save) {
                save.unlockedAchievements.append(a.id)
                recentlyUnlocked.append(a.id)
            }
        }
    }

    // MARK: - Progression helpers

    func record(for chapter: Int, level: Int) -> HJLevelRecord? {
        save.records["\(chapter)-\(level)"]
    }

    func totalStars() -> Int { HJAchievements.totalStars(save) }

    func isChapterUnlocked(_ chapter: Int) -> Bool {
        guard chapter < HJCatalog.chapters.count else { return false }
        return totalStars() >= HJCatalog.chapters[chapter].starsToUnlock
    }

    func isLevelUnlocked(chapter: Int, level: Int) -> Bool {
        guard isChapterUnlocked(chapter) else { return false }
        if level == 0 { return true }
        return (record(for: chapter, level: level - 1)?.stars ?? 0) >= 1
    }

    /// Report a campaign win. Returns earned stars.
    func reportCampaignWin(chapter: Int, level: Int, taps: Int, par: Int, usedUndo: Bool, boatsExited: Int, tugsUsed: Int, undos: Int) -> Int {
        let stars: Int
        if taps <= par { stars = 3 } else if taps <= par + 2 { stars = 2 } else { stars = 1 }
        let key = "\(chapter)-\(level)"
        let old = save.records[key]
        if old == nil || stars > (old?.stars ?? 0) || taps < (old?.bestTaps ?? Int.max) {
            save.records[key] = HJLevelRecord(stars: max(stars, old?.stars ?? 0),
                                              bestTaps: min(taps, old?.bestTaps ?? Int.max))
        }
        applyCommonWinStats(taps: taps, usedUndo: usedUndo, boatsExited: boatsExited, tugsUsed: tugsUsed, undos: undos)
        save.stats.levelsCleared += 1
        refreshAchievements()
        persist()
        return stars
    }

    func reportDailyWin(dayKey: Int, taps: Int, usedUndo: Bool, boatsExited: Int, tugsUsed: Int, undos: Int) {
        let keyStr = String(dayKey)
        let firstToday = save.bestDailyTaps[keyStr] == nil
        if firstToday {
            if save.lastDailyDayKey == dayKey - 1 {
                save.dailyStreak += 1
            } else if save.lastDailyDayKey != dayKey {
                save.dailyStreak = 1
            }
            save.lastDailyDayKey = dayKey
            save.stats.dailiesCompleted += 1
        }
        let best = save.bestDailyTaps[keyStr] ?? Int.max
        save.bestDailyTaps[keyStr] = min(best, taps)
        applyCommonWinStats(taps: taps, usedUndo: usedUndo, boatsExited: boatsExited, tugsUsed: tugsUsed, undos: undos)
        refreshAchievements()
        persist()
    }

    private func applyCommonWinStats(taps: Int, usedUndo: Bool, boatsExited: Int, tugsUsed: Int, undos: Int) {
        save.stats.totalTaps += taps
        save.stats.totalUndos += undos
        save.stats.boatsExited += boatsExited
        save.stats.tugsUsed += tugsUsed
        if !usedUndo { save.stats.winsWithoutUndo += 1 }
    }

    static func todayKey() -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.year, .month, .day], from: Date())
        let y = comps.year ?? 2026, m = comps.month ?? 1, d = comps.day ?? 1
        // Day-serial so consecutive days differ by exactly 1 (streak math).
        let base = cal.date(from: DateComponents(year: 2024, month: 1, day: 1)) ?? Date()
        let today = cal.date(from: DateComponents(year: y, month: m, day: d)) ?? Date()
        let days = cal.dateComponents([.day], from: base, to: today).day ?? 0
        return days
    }

    static func todayLabel() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM d"
        return f.string(from: Date())
    }
}
