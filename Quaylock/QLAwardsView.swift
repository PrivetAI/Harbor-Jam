import SwiftUI

struct QLAwardsView: View {
    @EnvironmentObject var store: QLStore
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        ZStack {
            QLTheme.chartDeep.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text("Awards")
                        .font(QLTheme.display(28))
                        .foregroundColor(QLTheme.cyanSoft)
                        .padding(.top, 12)

                    statsBlock
                        // A label/value row 880pt wide reads as two unrelated
                        // columns, so the log stays a narrow panel.
                        .hjCap(QLLayout.panelColumn, hSize)

                    achievementList
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
                .hjColumn(QLLayout.awardsColumn, hSize)
            }
        }
    }

    @ViewBuilder
    private var achievementList: some View {
        if QLLayout.wide(hSize) {
            LazyVGrid(columns: QLLayout.twoColumns(spacing: 10), spacing: 10) {
                ForEach(QLAchievements.all) { achievement in
                    achievementRow(achievement)
                }
            }
        } else {
            VStack(spacing: 10) {
                ForEach(QLAchievements.all) { achievement in
                    achievementRow(achievement)
                }
            }
        }
    }

    private var statsBlock: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Harbor Log")
                    .font(QLTheme.display(16))
                    .foregroundColor(QLTheme.cyanSoft)
                Spacer()
            }
            statRow("Shifts cleared", "\(store.save.stats.shiftsCleared)")
            statRow("Tons moved", "\(store.save.stats.tonsServed)")
            statRow("Ships worked", "\(store.save.stats.shipsServed)")
            statRow("Ships turned away", "\(store.save.stats.shipsLost)")
            statRow("Groundings", "\(store.save.stats.groundings)")
            statRow("Best Watch run", "\(store.save.watchBestTons) t")
            statRow("Stars collected", "\(store.totalStars())/\(QLCatalog.totalShifts * 3)")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(QLTheme.cardBG))
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(QLTheme.body(13))
                .foregroundColor(QLTheme.inkSoft)
            Spacer()
            Text(value)
                .font(QLTheme.mono(13))
                .foregroundColor(QLTheme.cyanSoft)
        }
    }

    private func achievementRow(_ achievement: QLAchievement) -> some View {
        let unlocked = store.save.unlockedAchievements.contains(achievement.id)
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(unlocked ? QLTheme.gold : QLTheme.cyanSoft.opacity(0.1))
                    .frame(width: 42, height: 42)
                QLTrophyShape()
                    .fill(unlocked ? QLTheme.cyanSoft : QLTheme.cyanSoft.opacity(0.3))
                    .frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title)
                    .font(QLTheme.body(14, weight: .bold))
                    .foregroundColor(unlocked ? QLTheme.cyanSoft : QLTheme.cyanSoft.opacity(0.55))
                Text(achievement.detail)
                    .font(QLTheme.body(12))
                    .foregroundColor(QLTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if unlocked {
                QLCheckShape()
                    .stroke(QLTheme.gold, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 16, height: 16)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(unlocked ? QLTheme.cardBG : Color.white.opacity(0.4)))
    }
}
