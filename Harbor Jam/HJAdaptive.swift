import SwiftUI
import UIKit

/// Single source of truth for the iPad (regular width) layout.
///
/// Every helper here is gated on `horizontalSizeClass == .regular` **and** the
/// device idiom being `.pad`. The idiom test is not redundant: an iPhone Plus /
/// Pro Max in landscape also reports a regular horizontal size class, and the
/// shipped, already-simulator-tested phone layout must not shift there. On
/// anything that is not a wide iPad canvas every helper below returns the view
/// completely untouched, so the iPhone rendering is byte-identical to 1.0.
/// Height of the top safe area, read from the key window.
///
/// This app hides every navigation bar, so scrolled content draws straight over
/// the clock unless something opaque covers the inset. A `GeometryReader` cannot
/// supply it here: inside a view that already ignores the safe area it reports
/// zero.
enum HJSafeArea {
    static var top: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .safeAreaInsets.top ?? 47
    }
}

enum HJLayout {

    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// True only on an iPad running at regular width (full screen, or a
    /// wide-enough Split View slot). A Slide Over / narrow Split View slot
    /// reports compact and therefore keeps the phone layout.
    static func wide(_ h: UserInterfaceSizeClass?) -> Bool {
        h == .regular && isPad
    }

    // MARK: - Column caps
    //
    // All of these are OUTER widths, i.e. they include the 16pt page padding
    // the screens already apply. They are max-width caps, never fixed padding,
    // so a narrower regular canvas (iPad mini portrait at 744pt, a 2/3 Split
    // View slot) simply uses what it has.

    /// Harbor: chapter cards laid out two-up.
    static let harborColumn: CGFloat = 920
    /// Awards: stats block plus a two-up achievement grid.
    static let awardsColumn: CGFloat = 880
    /// More: settings + the two-up Harbor Manual codex.
    static let moreColumn: CGFloat = 820
    /// Level grid inside a chapter — the adaptive 64pt cells fan out to nine
    /// per row at this width instead of the phone's four.
    static let levelGridColumn: CGFloat = 720
    /// Cards that read as a single settings/about panel inside a wider page.
    static let panelColumn: CGFloat = 700
    /// Daily Jam: one banner-led hero, deliberately narrow.
    static let dailyColumn: CGFloat = 620
    /// Game screen header / HUD / control rows. The board is capped separately
    /// (see `boardColumn`) because it wants far more of the canvas than these.
    static let gameChromeColumn: CGFloat = 760
    /// Custom tab bar contents. The white background still spans full width.
    static let tabBarColumn: CGFloat = 640
    /// Win + onboarding overlay cards. Each card already applies its own
    /// horizontal padding inside this, so the visible card is ~460pt.
    static let overlayColumn: CGFloat = 520

    // MARK: - Marina board

    /// Widest slice of the canvas the marina board may claim. On a 12.9" iPad
    /// (1024pt portrait) the un-capped board would run 976pt edge to edge; 920
    /// keeps a margin of harbour water around the driftwood frame.
    static let boardColumn: CGFloat = 920

    /// Ceiling on a single grid cell. Without it a 6x6 harbour on a 12.9" iPad
    /// would draw 149pt cells; with it small boards settle at 792pt and the
    /// 9x9 boards still reach the full 896pt. Never consulted on iPhone.
    static let maxCell: CGFloat = 132

    /// Reference board width for the art-weight scale factor.
    ///
    /// The board is always width-bound in portrait: `HJGameView` hands the
    /// board `geo.width - 24` and `HJBoardView` takes another 24 of padding, so
    /// on the widest iPhone that exists (440pt — 16/17 Pro Max) the board is
    /// 440 - 24 - 24 = 392pt across, and every narrower iPhone is smaller
    /// still. 392 / 420 = 0.93, so `max(1, ...)` pins the factor to exactly 1
    /// on every iPhone in both orientations even before the `wide()` gate.
    static let artReference: CGFloat = 420

    /// Upper clamp on the art scale. The largest board this app can produce is
    /// 896pt (9x9 on a 12.9" iPad in portrait) -> 896 / 420 = 2.13, so the
    /// clamp is a backstop rather than something reachable today.
    static let maxArtScale: CGFloat = 2.2

    // MARK: - Grids

    /// Two equal columns for the card lists that become a grid on iPad.
    static func twoColumns(spacing: CGFloat) -> [GridItem] {
        [GridItem(.flexible(), spacing: spacing, alignment: .top),
         GridItem(.flexible(), spacing: spacing, alignment: .top)]
    }
}

extension View {
    /// Caps this view at `width` and re-centres it inside the full available
    /// width. Returns `self` unchanged on iPhone / compact width.
    @ViewBuilder
    func hjColumn(_ width: CGFloat, _ h: UserInterfaceSizeClass?) -> some View {
        if HJLayout.wide(h) {
            self.frame(maxWidth: width).frame(maxWidth: .infinity)
        } else {
            self
        }
    }

    /// Caps this view at `width` without pushing it back out to full width —
    /// for panels that already sit inside a centred column.
    @ViewBuilder
    func hjCap(_ width: CGFloat, _ h: UserInterfaceSizeClass?) -> some View {
        if HJLayout.wide(h) {
            self.frame(maxWidth: width)
        } else {
            self
        }
    }
}
