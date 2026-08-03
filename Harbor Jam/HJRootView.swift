import SwiftUI

struct HJRootView: View {
    @EnvironmentObject var store: HJStore
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            HJTheme.chartDeep.ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch selectedTab {
                    case 0:
                        NavigationView { HJPortsView() }
                            .navigationViewStyle(StackNavigationViewStyle())
                    case 1:
                        NavigationView { HJWatchPlaceholder() }
                            .navigationViewStyle(StackNavigationViewStyle())
                    case 2:
                        NavigationView { HJAwardsView() }
                            .navigationViewStyle(StackNavigationViewStyle())
                    default:
                        NavigationView { HJMoreView() }
                            .navigationViewStyle(StackNavigationViewStyle())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            tabBar
        }
        .preferredColorScheme(.dark)
        .onAppear {
            #if DEBUG
            assert(HJSprite.missing.isEmpty, "missing sprites: \(HJSprite.missing)")
            #endif
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(index: 0, label: "Ports") {
                AnyView(HJWaveShape()
                    .stroke(iconColor(0), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: 26, height: 17))
            }
            tabButton(index: 1, label: "Watch") {
                AnyView(HJPulseShape()
                    .stroke(iconColor(1), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(width: 24, height: 18))
            }
            tabButton(index: 2, label: "Awards") {
                AnyView(HJTrophyShape()
                    .fill(iconColor(2))
                    .frame(width: 22, height: 22))
            }
            tabButton(index: 3, label: "More") {
                AnyView(HJGearShape()
                    .fill(iconColor(3))
                    .frame(width: 22, height: 22))
            }
        }
        // iPad: four tabs spread across 1024pt would strand each label in its
        // own quadrant. Cap the button row and re-centre it — the cap applies
        // BEFORE the padding/background so the bar still spans full width.
        .hjColumn(HJLayout.tabBarColumn, hSize)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            HJTheme.cardBG
                .overlay(Rectangle().fill(HJTheme.contour.opacity(0.5)).frame(height: 1), alignment: .top)
                .edgesIgnoringSafeArea(.bottom)
        )
    }

    private func iconColor(_ index: Int) -> Color {
        selectedTab == index ? HJTheme.cyan : HJTheme.cyanSoft.opacity(0.35)
    }

    private func tabButton(index: Int, label: String, @ViewBuilder icon: () -> AnyView) -> some View {
        Button(action: { selectedTab = index }) {
            VStack(spacing: 4) {
                icon()
                    .frame(height: 24)
                Text(label)
                    .font(HJTheme.body(10, weight: selectedTab == index ? .bold : .medium))
                    .foregroundColor(iconColor(index))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
    }
}

/// Replaced by `HJWatchView` in the endless-mode task. Present so the app builds
/// and runs at every commit rather than only at the end.
private struct HJWatchPlaceholder: View {
    var body: some View {
        ZStack {
            HJTheme.chartDeep.ignoresSafeArea()
            Text("Watch")
                .font(HJTheme.display(24))
                .foregroundColor(HJTheme.cyan)
        }
        .navigationBarHidden(true)
    }
}
