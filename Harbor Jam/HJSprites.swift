import SwiftUI
#if DEBUG
import UIKit
#endif

/// Every bundled sprite name lives here and nowhere else. A typo becomes a
/// compile error rather than a silently blank image — `actool` drops an SVG it
/// cannot parse with only a warning, and the result renders as empty space.
enum HJSprite: String, CaseIterable {
    case hull2 = "hull_2"
    case hull3 = "hull_3"
    case hull4 = "hull_4"
    case hull5 = "hull_5"

    case cargoContainer = "cargo_container"
    case cargoBulk = "cargo_bulk"
    case cargoLiquid = "cargo_liquid"

    case berthEmpty = "berth_empty"
    case berthCrane = "berth_crane"
    case berthConveyor = "berth_conveyor"
    case berthPipeline = "berth_pipeline"

    case buoyPort = "buoy_port"
    case buoyStarboard = "buoy_starboard"
    case buoyCardinal = "buoy_cardinal"

    case tug = "tug"

    case iconTonnage = "icon_tonnage"
    case iconReputation = "icon_reputation"
    case iconTide = "icon_tide"
    case iconCoin = "icon_coin"

    case compassRose = "compass_rose"
    case depthContours = "depth_contours"

    var image: Image { Image(rawValue) }

    /// Hull art for a given length, clamped to what exists.
    static func hull(length: Int) -> HJSprite {
        switch max(2, min(5, length)) {
        case 2: return .hull2
        case 3: return .hull3
        case 4: return .hull4
        default: return .hull5
        }
    }

    static func cargo(_ cargo: HJCargo) -> HJSprite {
        switch cargo {
        case .container: return .cargoContainer
        case .bulk: return .cargoBulk
        case .liquid: return .cargoLiquid
        }
    }

    static func berth(_ equipment: HJEquipment) -> HJSprite {
        switch equipment {
        case .none: return .berthEmpty
        case .crane: return .berthCrane
        case .conveyor: return .berthConveyor
        case .pipeline: return .berthPipeline
        }
    }
}

#if DEBUG
extension HJSprite {
    /// Names any sprite whose asset did not make it into the bundle.
    static var missing: [String] {
        allCases.map(\.rawValue).filter { UIImage(named: $0) == nil }
    }
}
#endif
