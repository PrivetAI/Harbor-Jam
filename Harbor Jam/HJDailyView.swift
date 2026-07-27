import SwiftUI

struct HJDailyView: View {
    @EnvironmentObject var store: HJStore
    @Environment(\.horizontalSizeClass) private var hSize

    private var todayKey: Int { HJStore.todayKey() }
    private var doneToday: Bool { store.save.bestDailyTaps[String(todayKey)] != nil }

    var body: some View {
        ZStack {
            HJTheme.cream.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Text("Daily Jam")
                        .font(HJTheme.display(28))
                        .foregroundColor(HJTheme.navy)
                        .padding(.top, 12)
                    Text(HJStore.todayLabel())
                        .font(HJTheme.body(14, weight: .semibold))
                        .foregroundColor(HJTheme.inkSoft)

                    ZStack {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(HJTheme.navy)
                        VStack(spacing: 14) {
                            HJWaveShape()
                                .stroke(HJTheme.seafoam, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 70, height: 34)
                            Text("A fresh harbor every day")
                                .font(HJTheme.display(18))
                                .foregroundColor(.white)
                            Text("One handcrafted-feel jam, seeded by the date.\nSame board for everyone, once per day.")
                                .font(HJTheme.body(12))
                                .foregroundColor(Color.white.opacity(0.75))
                                .multilineTextAlignment(.center)

                            if doneToday {
                                VStack(spacing: 4) {
                                    HStack(spacing: 6) {
                                        HJCheckShape()
                                            .stroke(HJTheme.seafoam, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                                            .frame(width: 16, height: 16)
                                        Text("Cleared today")
                                            .font(HJTheme.body(14, weight: .bold))
                                            .foregroundColor(HJTheme.seafoam)
                                    }
                                    if let best = store.save.bestDailyTaps[String(todayKey)] {
                                        Text("Best: \(best) moves")
                                            .font(HJTheme.mono(13))
                                            .foregroundColor(Color.white.opacity(0.8))
                                    }
                                    Text("Replay to improve your best")
                                        .font(HJTheme.body(11))
                                        .foregroundColor(Color.white.opacity(0.6))
                                }
                            }

                            NavigationLink(destination: dailyDestination) {
                                Text(doneToday ? "Play Again" : "Play Today's Jam")
                                    .font(HJTheme.body(16, weight: .bold))
                                    .foregroundColor(HJTheme.navy)
                                    .padding(.horizontal, 30).padding(.vertical, 13)
                                    .background(Capsule().fill(HJTheme.sunGold))
                            }
                        }
                        .padding(24)
                    }
                    .padding(.horizontal, 4)

                    HStack(spacing: 12) {
                        statCard(title: "Streak", value: "\(store.save.dailyStreak)",
                                 caption: store.save.dailyStreak == 1 ? "day" : "days")
                        statCard(title: "Dailies Cleared", value: "\(store.save.stats.dailiesCompleted)", caption: "total")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
                // One hero card and two stat tiles — this page wants to stay
                // narrow and centred, not stretch to 1024pt.
                .hjColumn(HJLayout.dailyColumn, hSize)
            }
        }
    }

    @ViewBuilder
    private var dailyDestination: some View {
        if let game = HJGameView(mode: .daily(dayKey: todayKey), store: store,
                                 title: "Daily · \(HJStore.todayLabel())") {
            game.environmentObject(store)
        } else {
            Text("Daily unavailable")
                .font(HJTheme.body(15))
                .foregroundColor(HJTheme.inkSoft)
        }
    }

    private func statCard(title: String, value: String, caption: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(HJTheme.body(11, weight: .bold))
                .foregroundColor(HJTheme.inkSoft)
            Text(value)
                .font(HJTheme.mono(24))
                .foregroundColor(HJTheme.navy)
            Text(caption)
                .font(HJTheme.body(11))
                .foregroundColor(HJTheme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 16).fill(HJTheme.cardBG))
    }
}
