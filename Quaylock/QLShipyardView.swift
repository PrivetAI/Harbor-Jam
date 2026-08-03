import SwiftUI

struct QLShipyardView: View {
    @EnvironmentObject var store: QLStore
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        ZStack {
            QLTheme.chartDeep.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    header
                    ForEach(QLUpgradeLine.allCases) { line in
                        upgradeRow(line)
                    }
                    Text("Upgrades apply to every campaign shift. The Watch has its own, for that run only.")
                        .font(QLTheme.body(11))
                        .foregroundColor(QLTheme.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .hjColumn(QLLayout.panelColumn, hSize)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shipyard")
                    .font(QLTheme.display(24))
                    .foregroundColor(QLTheme.cyanSoft)
                Text("Spend the harbour's takings")
                    .font(QLTheme.body(12))
                    .foregroundColor(QLTheme.inkSoft)
            }
            Spacer()
            HStack(spacing: 5) {
                QLSprite.iconCoin.image
                    .resizable().scaledToFit().frame(width: 20, height: 20)
                Text("\(store.save.coins)")
                    .font(QLTheme.mono(16))
                    .foregroundColor(QLTheme.gold)
            }
        }
        .padding(.top, 8)
    }

    private func upgradeRow(_ line: QLUpgradeLine) -> some View {
        let level = store.upgradeLevel(line)
        let maxed = level >= line.maxLevel
        let cost = line.cost(atLevel: level)
        let affordable = store.save.coins >= cost
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.title)
                        .font(QLTheme.display(16))
                        .foregroundColor(QLTheme.cyanSoft)
                    Text(line.detail)
                        .font(QLTheme.body(12))
                        .foregroundColor(QLTheme.inkSoft)
                }
                Spacer()
                Button(action: { store.buyUpgrade(line) }) {
                    VStack(spacing: 1) {
                        Text(maxed ? "Max" : "Buy")
                            .font(QLTheme.body(13, weight: .semibold))
                        if !maxed {
                            Text("\(cost)")
                                .font(QLTheme.mono(11))
                        }
                    }
                    .foregroundColor(maxed || !affordable ? QLTheme.inkSoft : QLTheme.chartDeep)
                    .frame(width: 72, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(maxed || !affordable ? QLTheme.chartGrid : QLTheme.cyan))
                    .contentShape(Rectangle())
                }
                .disabled(maxed || !affordable)
            }
            HStack(spacing: 5) {
                ForEach(0..<line.maxLevel, id: \.self) { i in
                    Capsule()
                        .fill(i < level ? QLTheme.gold : QLTheme.chartGrid)
                        .frame(height: 5)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(QLTheme.cardBG))
    }
}
