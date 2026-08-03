import SwiftUI

struct QLRootView: View {
    @EnvironmentObject var store: QLStore
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var selectedTab = 0

    var body: some View {
        // `safeAreaInset` rather than a ZStack overlay or a plain VStack row.
        // `NavigationView` on iOS 15 hosts a UINavigationController whose view
        // reaches past its SwiftUI frame and swallows touches on anything
        // stacked beside it — the bar drew correctly but its buttons never
        // fired, as an overlay, as a VStack sibling, with Button and with
        // onTapGesture alike. safeAreaInset is the one arrangement UIKit is
        // told about, so the bar both lays out and receives taps.
        Group {
            switch selectedTab {
            case 0:
                NavigationView { QLPortsView() }
                    .navigationViewStyle(StackNavigationViewStyle())
            case 1:
                NavigationView { QLWatchView() }
                    .navigationViewStyle(StackNavigationViewStyle())
            case 2:
                NavigationView { QLAwardsView() }
                    .navigationViewStyle(StackNavigationViewStyle())
            default:
                NavigationView { QLMoreView() }
                    .navigationViewStyle(StackNavigationViewStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // NO opaque band over the top safe area here, deliberately. Scrolled
        // content does pass under the clock, which is ordinary for a full-bleed
        // scroll view — but every band formulation tried (ZStack sibling, root
        // overlay, content-scoped overlay, with and without
        // `allowsHitTesting(false)`) killed the tab bar outright: `ignoresSafeArea`
        // lets the band escape its container and eat the bar's touches, and the
        // bar then draws normally while doing nothing. A cosmetic bleed beats a
        // dead tab bar. Fix it per screen, inside each ScrollView, if at all.
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        .background(QLTheme.chartDeep.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            #if DEBUG
            assert(QLSprite.missing.isEmpty, "missing sprites: \(QLSprite.missing)")
            #endif
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(index: 0, label: "Ports") {
                AnyView(QLWaveShape()
                    .stroke(iconColor(0), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: 26, height: 17))
            }
            tabButton(index: 1, label: "Watch") {
                AnyView(QLPulseShape()
                    .stroke(iconColor(1), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(width: 24, height: 18))
            }
            tabButton(index: 2, label: "Awards") {
                AnyView(QLTrophyShape()
                    .fill(iconColor(2))
                    .frame(width: 22, height: 22))
            }
            tabButton(index: 3, label: "More") {
                AnyView(QLGearShape()
                    .fill(iconColor(3))
                    .frame(width: 22, height: 22))
            }
        }
        // iPad: four tabs spread across 1024pt would strand each label in its
        // own quadrant. Cap the button row and re-centre it — the cap applies
        // BEFORE the padding/background so the bar still spans full width.
        .hjColumn(QLLayout.tabBarColumn, hSize)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            QLTheme.cardBG
                .overlay(Rectangle().fill(QLTheme.contour.opacity(0.5)).frame(height: 1), alignment: .top)
                .edgesIgnoringSafeArea(.bottom)
        )
    }

    private func iconColor(_ index: Int) -> Color {
        selectedTab == index ? QLTheme.cyan : QLTheme.cyanSoft.opacity(0.35)
    }

    /// A plain tappable cell rather than a `Button`. The Button form stopped
    /// delivering its action here entirely — the label drew, the row laid out,
    /// and taps went nowhere — while a bare `onTapGesture` on the same shape
    /// works. Keep the explicit contentShape: the label is a Shape plus text
    /// over empty space, which on its own has almost no hit area.
    private func tabButton(index: Int, label: String, @ViewBuilder icon: () -> AnyView) -> some View {
        VStack(spacing: 4) {
            icon()
                .frame(height: 24)
            Text(label)
                .font(QLTheme.body(10, weight: selectedTab == index ? .bold : .medium))
                .foregroundColor(iconColor(index))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .contentShape(Rectangle())
        .onTapGesture { selectedTab = index }
    }
}

