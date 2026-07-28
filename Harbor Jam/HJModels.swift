import Foundation
import CoreGraphics

enum HJDirection: Int, Codable, CaseIterable {
    case north = 0, east = 1, south = 2, west = 3

    var dx: Int {
        switch self {
        case .east: return 1
        case .west: return -1
        default: return 0
        }
    }
    var dy: Int {
        switch self {
        case .south: return 1
        case .north: return -1
        default: return 0
        }
    }
    var rotatedCW: HJDirection {
        HJDirection(rawValue: (rawValue + 1) % 4) ?? .north
    }
    /// A 180° turn. Unlike `rotatedCW` this preserves a hull's footprint — east↔west and
    /// north↔south are both length-along-the-same-axis — which is why a turning basin
    /// never needs a collision check.
    var opposite: HJDirection {
        HJDirection(rawValue: (rawValue + 2) % 4) ?? .north
    }
    var isHorizontal: Bool { self == .east || self == .west }
}

struct HJCell: Hashable, Codable {
    var x: Int
    var y: Int
}

struct HJBoat: Codable, Identifiable, Equatable {
    var id: Int
    var x: Int          // top-left of footprint
    var y: Int
    var length: Int     // 2 or 3 for 1×N; 2 for barge (2×2)
    var isBarge: Bool
    var bow: HJDirection
    var hullIndex: Int      // color/pattern index
    var anchoredBy: Int?    // boat id that must exit before this one can move
    /// Cells this hull advances per tap, printed on the deck as pips. This is the whole
    /// puzzle: a boat that stops short lands on cells that were free a moment ago, so a
    /// legal-looking tap can plug the only lane another boat needs.
    var throttle: Int

    var width: Int { isBarge ? 2 : (bow.isHorizontal ? length : 1) }
    var height: Int { isBarge ? 2 : (bow.isHorizontal ? 1 : length) }

    var cells: [HJCell] {
        var out: [HJCell] = []
        for dx in 0..<width {
            for dy in 0..<height {
                out.append(HJCell(x: x + dx, y: y + dy))
            }
        }
        return out
    }
}

struct HJCurrentLane: Codable, Equatable {
    var isRow: Bool
    var index: Int              // row y or column x
    var push: HJDirection       // perpendicular push direction
    var period: Int             // ticks before the push reverses; 0 means it never does

    /// The push actually in force at `tick`. Reversing on a period stops a lane from
    /// saturating against a wall, and makes the board change while the player watches.
    func effectivePush(atTick tick: Int) -> HJDirection {
        guard period > 0 else { return push }
        return (tick / period) % 2 == 1 ? push.opposite : push
    }
}

struct HJFerry: Codable, Equatable {
    var row: Int
    var x: Int                  // leading cell x
    var length: Int             // 2
    var stride: Int             // cells advanced per player move
}

// Static definition of a level's mechanics envelope (fed to the generator).
struct HJLevelConfig {
    var gridW: Int
    var gridH: Int
    var boatCount: Int
    var bargeCount: Int
    var useCurrents: Bool
    var useTide: Bool
    var useFerry: Bool
    var chainCount: Int         // buoy anchor chains
    var basinCount: Int         // turning-basin cells: enter one and the bow flips 180°
    var night: Bool
}

struct HJChapterDef {
    var index: Int
    var name: String
    var tagline: String
    var starsToUnlock: Int
}

enum HJCatalog {
    static let chapters: [HJChapterDef] = [
        HJChapterDef(index: 0, name: "Quiet Cove", tagline: "Learn the ropes", starsToUnlock: 0),
        HJChapterDef(index: 1, name: "Fisher Wharf", tagline: "Mind the currents", starsToUnlock: 18),
        HJChapterDef(index: 2, name: "Ferry Port", tagline: "Time the crossings", starsToUnlock: 42),
        HJChapterDef(index: 3, name: "Tide Flats", tagline: "Watch the water line", starsToUnlock: 70),
        HJChapterDef(index: 4, name: "Storm Marina", tagline: "Chained and crowded", starsToUnlock: 100),
        HJChapterDef(index: 5, name: "Night Harbor", tagline: "Lanterns on the water", starsToUnlock: 132),
        HJChapterDef(index: 6, name: "Grand Regatta", tagline: "Everything at once", starsToUnlock: 166),
    ]
    static let levelsPerChapter = 20
    static var totalLevels: Int { chapters.count * levelsPerChapter }

    /// Boards cap at 8x8 and 10 boats. On a 393pt iPhone a 9x9 grid gives a 38pt cell and
    /// a 35pt hull, under the 44pt touch target — and more boats simply means more
    /// simultaneously-correct taps, which made the old game EASIER as it went on.
    /// Difficulty now comes from throttle, basins and the acceptance gate, not object count.
    static func config(chapter: Int, level: Int) -> HJLevelConfig {
        let t = Double(level) / Double(levelsPerChapter - 1)   // 0..1 inside chapter
        func ramp(_ a: Int, _ b: Int) -> Int { a + Int((Double(b - a) * t).rounded()) }
        switch chapter {
        case 0:
            return HJLevelConfig(gridW: 6, gridH: 6, boatCount: ramp(3, 6), bargeCount: 0,
                                 useCurrents: false, useTide: false, useFerry: false,
                                 chainCount: 0, basinCount: 1, night: false)
        case 1:
            return HJLevelConfig(gridW: 6, gridH: 7, boatCount: ramp(4, 7), bargeCount: level >= 12 ? 1 : 0,
                                 useCurrents: true, useTide: false, useFerry: false,
                                 chainCount: 0, basinCount: 1, night: false)
        case 2:
            return HJLevelConfig(gridW: 7, gridH: 7, boatCount: ramp(5, 8), bargeCount: level >= 10 ? 1 : 0,
                                 useCurrents: false, useTide: false, useFerry: true,
                                 chainCount: 0, basinCount: 2, night: false)
        case 3:
            return HJLevelConfig(gridW: 7, gridH: 8, boatCount: ramp(5, 8), bargeCount: 1,
                                 useCurrents: false, useTide: true, useFerry: false,
                                 chainCount: 0, basinCount: ramp(2, 3), night: false)
        case 4:
            return HJLevelConfig(gridW: 8, gridH: 8, boatCount: ramp(6, 9), bargeCount: 1,
                                 useCurrents: true, useTide: true, useFerry: false,
                                 chainCount: level >= 6 ? 2 : 1, basinCount: ramp(2, 3), night: false)
        case 5:
            return HJLevelConfig(gridW: 8, gridH: 8, boatCount: ramp(7, 10), bargeCount: 1,
                                 useCurrents: true, useTide: false, useFerry: true,
                                 chainCount: 1, basinCount: 3, night: true)
        default:
            return HJLevelConfig(gridW: 8, gridH: 8, boatCount: ramp(8, 10), bargeCount: 2,
                                 useCurrents: true, useTide: true, useFerry: true,
                                 chainCount: 2, basinCount: ramp(3, 4), night: false)
        }
    }

    static func seed(chapter: Int, level: Int) -> UInt64 {
        UInt64(0x48_4A) &* 0x9E3779B97F4A7C15 &+ UInt64(chapter) &* 7919 &+ UInt64(level) &* 104729 &+ 17
    }

    /// Pre-verified daily fallback pool (30 seeds over a mid-difficulty config).
    static let dailyFallbackSeeds: [UInt64] = (0..<30).map {
        UInt64(0xDA_11) &* 0x9E3779B97F4A7C15 &+ UInt64($0) &* 6151 &+ 3
    }

    static let dailyConfig = HJLevelConfig(gridW: 7, gridH: 8, boatCount: 9, bargeCount: 1,
                                           useCurrents: true, useTide: true, useFerry: false,
                                           chainCount: 1, basinCount: 2, night: false)
}
