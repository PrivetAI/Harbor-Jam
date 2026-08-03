import SwiftUI

/// Every bundled sprite name lives here and nowhere else. A typo becomes a
/// compile error rather than a silently blank image.
enum HJSprite: String {
    case hull4 = "hull_4"

    var image: Image { Image(rawValue) }
}
