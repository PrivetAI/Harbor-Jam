import SwiftUI

struct QLRootView: View {
    @EnvironmentObject var store: QLStore
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            QLTheme.chartDeep.ignoresSafeArea()

            VStack(spacing: 0) {
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
            }

            tabBar

            // LAST sibling on purpose: an opaque band over the top safe area, so
            // scrolled content stops drawing across the clock. Anything added
            // after this would sit under it.
            VStack(spacing: 0) {
                QLTheme.chartDeep
                    .frame(height: QLSafeArea.top)
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
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

    private func tabButton(index: Int, label: String, @ViewBuilder icon: () -> AnyView) -> some View {
        Button(action: { selectedTab = index }) {
            VStack(spacing: 4) {
                icon()
                    .frame(height: 24)
                Text(label)
                    .font(QLTheme.body(10, weight: selectedTab == index ? .bold : .medium))
                    .foregroundColor(iconColor(index))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
    }
}

