import SwiftUI

struct HJAwardsView: View {
    @EnvironmentObject var store: HJStore
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        ZStack {
            HJTheme.chartDeep.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text("Awards")
                        .font(HJTheme.display(28))
                        .foregroundColor(HJTheme.cyanSoft)
                        .padding(.top, 12)

                    statsBlock
                        // A label/value row 880pt wide reads as two unrelated
                        // columns, so the log stays a narrow panel.
                        .hjCap(HJLayout.panelColumn, hSize)

                    achievementList
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
                .hjColumn(HJLayout.awardsColumn, hSize)
            }
        }
    }

    @ViewBuilder
    private var achievementList: some View {
        if HJLayout.wide(hSize) {
            LazyVGrid(columns: HJLayout.twoColumns(spacing: 10), spacing: 10) {
                ForEach(HJAchievements.all) { achievement in
                    achievementRow(achievement)
                }
            }
        } else {
            VStack(spacing: 10) {
                ForEach(HJAchievements.all) { achievement in
                    achievementRow(achievement)
                }
            }
        }
    }

    private var statsBlock: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Harbor Log")
                    .font(HJTheme.display(16))
                    .foregroundColor(HJTheme.cyanSoft)
                Spacer()
            }
            statRow("Shifts cleared", "\(store.save.stats.shiftsCleared)")
            statRow("Tons moved", "\(store.save.stats.tonsServed)")
            statRow("Ships worked", "\(store.save.stats.shipsServed)")
            statRow("Ships turned away", "\(store.save.stats.shipsLost)")
            statRow("Groundings", "\(store.save.stats.groundings)")
            statRow("Best Watch run", "\(store.save.watchBestTons) t")
            statRow("Stars collected", "\(store.totalStars())/\(HJCatalog.totalShifts * 3)")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(HJTheme.cardBG))
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(HJTheme.body(13))
                .foregroundColor(HJTheme.inkSoft)
            Spacer()
            Text(value)
                .font(HJTheme.mono(13))
                .foregroundColor(HJTheme.cyanSoft)
        }
    }

    private func achievementRow(_ achievement: HJAchievement) -> some View {
        let unlocked = store.save.unlockedAchievements.contains(achievement.id)
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(unlocked ? HJTheme.gold : HJTheme.cyanSoft.opacity(0.1))
                    .frame(width: 42, height: 42)
                HJTrophyShape()
                    .fill(unlocked ? HJTheme.cyanSoft : HJTheme.cyanSoft.opacity(0.3))
                    .frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title)
                    .font(HJTheme.body(14, weight: .bold))
                    .foregroundColor(unlocked ? HJTheme.cyanSoft : HJTheme.cyanSoft.opacity(0.55))
                Text(achievement.detail)
                    .font(HJTheme.body(12))
                    .foregroundColor(HJTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if unlocked {
                HJCheckShape()
                    .stroke(HJTheme.gold, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 16, height: 16)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(unlocked ? HJTheme.cardBG : Color.white.opacity(0.4)))
    }
}
