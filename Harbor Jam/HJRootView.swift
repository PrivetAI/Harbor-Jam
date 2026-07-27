import SwiftUI

struct HJRootView: View {
    @EnvironmentObject var store: HJStore
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Group {
                    switch selectedTab {
                    case 0:
                        NavigationView { HJHarborView() }
                            .navigationViewStyle(StackNavigationViewStyle())
                    case 1:
                        NavigationView { HJDailyView() }
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
        .preferredColorScheme(.light)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(index: 0, label: "Harbor") {
                AnyView(HJWaveShape()
                    .stroke(iconColor(0), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: 26, height: 17))
            }
            tabButton(index: 1, label: "Daily") {
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
        // own quadrant. Cap the button row and re-centre it — the cap is applied
        // BEFORE the padding/background so the white bar still spans full width.
        .hjColumn(HJLayout.tabBarColumn, hSize)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            Color.white
                .shadow(color: HJTheme.navy.opacity(0.08), radius: 8, y: -3)
                .edgesIgnoringSafeArea(.bottom)
        )
    }

    private func iconColor(_ index: Int) -> Color {
        selectedTab == index ? HJTheme.navy : HJTheme.navy.opacity(0.35)
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
        }
    }
}
