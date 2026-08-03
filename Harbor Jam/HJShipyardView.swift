import SwiftUI

struct HJShipyardView: View {
    @EnvironmentObject var store: HJStore
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        ZStack {
            HJTheme.chartDeep.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    header
                    ForEach(HJUpgradeLine.allCases) { line in
                        upgradeRow(line)
                    }
                    Text("Upgrades apply to every campaign shift. The Watch has its own, for that run only.")
                        .font(HJTheme.body(11))
                        .foregroundColor(HJTheme.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 112)
                .hjColumn(HJLayout.panelColumn, hSize)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shipyard")
                    .font(HJTheme.display(24))
                    .foregroundColor(HJTheme.cyanSoft)
                Text("Spend the harbour's takings")
                    .font(HJTheme.body(12))
                    .foregroundColor(HJTheme.inkSoft)
            }
            Spacer()
            HStack(spacing: 5) {
                HJSprite.iconCoin.image
                    .resizable().scaledToFit().frame(width: 20, height: 20)
                Text("\(store.save.coins)")
                    .font(HJTheme.mono(16))
                    .foregroundColor(HJTheme.gold)
            }
        }
        .padding(.top, 8)
    }

    private func upgradeRow(_ line: HJUpgradeLine) -> some View {
        let level = store.upgradeLevel(line)
        let maxed = level >= line.maxLevel
        let cost = line.cost(atLevel: level)
        let affordable = store.save.coins >= cost
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.title)
                        .font(HJTheme.display(16))
                        .foregroundColor(HJTheme.cyanSoft)
                    Text(line.detail)
                        .font(HJTheme.body(12))
                        .foregroundColor(HJTheme.inkSoft)
                }
                Spacer()
                Button(action: { store.buyUpgrade(line) }) {
                    VStack(spacing: 1) {
                        Text(maxed ? "Max" : "Buy")
                            .font(HJTheme.body(13, weight: .semibold))
                        if !maxed {
                            Text("\(cost)")
                                .font(HJTheme.mono(11))
                        }
                    }
                    .foregroundColor(maxed || !affordable ? HJTheme.inkSoft : HJTheme.chartDeep)
                    .frame(width: 72, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(maxed || !affordable ? HJTheme.chartGrid : HJTheme.cyan))
                    .contentShape(Rectangle())
                }
                .disabled(maxed || !affordable)
            }
            HStack(spacing: 5) {
                ForEach(0..<line.maxLevel, id: \.self) { i in
                    Capsule()
                        .fill(i < level ? HJTheme.gold : HJTheme.chartGrid)
                        .frame(height: 5)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(HJTheme.cardBG))
    }
}
