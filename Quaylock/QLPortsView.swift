import SwiftUI

struct QLPortsView: View {
    @EnvironmentObject var store: QLStore
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        ZStack {
            QLTheme.chartDeep.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    shipyardBar
                    ForEach(QLCatalog.ports, id: \.index) { port in
                        portCard(port)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 112)
                .hjColumn(QLLayout.harborColumn, hSize)
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quaylock")
                    .font(QLTheme.display(30))
                    .foregroundColor(QLTheme.cyanSoft)
                Text("Berth them, work them, get them out")
                    .font(QLTheme.body(13))
                    .foregroundColor(QLTheme.inkSoft)
            }
            Spacer()
            VStack(spacing: 2) {
                QLStarIcon(size: 20, filled: true)
                Text("\(store.totalStars())")
                    .font(QLTheme.mono(15))
                    .foregroundColor(QLTheme.cyanSoft)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(QLTheme.cardBG))
        }
        .padding(.top, 10)
    }

    private var shipyardBar: some View {
        NavigationLink(destination: QLShipyardView()) {
            HStack {
                QLSprite.iconCoin.image
                    .resizable().scaledToFit().frame(width: 20, height: 20)
                Text("\(store.save.coins)")
                    .font(QLTheme.mono(15))
                    .foregroundColor(QLTheme.gold)
                Spacer()
                Text("Shipyard")
                    .font(QLTheme.body(14, weight: .semibold))
                    .foregroundColor(QLTheme.cyanSoft)
                QLChevronShape()
                    .stroke(QLTheme.cyan, lineWidth: 2)
                    .frame(width: 8, height: 13)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(QLTheme.cardBG))
            .contentShape(Rectangle())
        }
    }

    private func portCard(_ port: QLPortTemplate) -> some View {
        let unlocked = store.isPortUnlocked(port.index)
        let stars = store.portStars(port.index)
        let maxStars = QLCatalog.shiftsPerPort * 3
        return Group {
            if unlocked {
                NavigationLink(destination: QLShiftGridView(port: port)) {
                    portCardBody(port, unlocked: true, stars: stars, maxStars: maxStars)
                }
            } else {
                portCardBody(port, unlocked: false, stars: stars, maxStars: maxStars)
            }
        }
    }

    private func portCardBody(_ port: QLPortTemplate, unlocked: Bool,
                              stars: Int, maxStars: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(unlocked ? QLTheme.hullFill : QLTheme.chartGrid)
                    .frame(width: 54, height: 54)
                if unlocked {
                    QLWaveShape()
                        .stroke(QLTheme.cyan, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .frame(width: 28, height: 18)
                } else {
                    QLLockShape()
                        .stroke(QLTheme.inkSoft, lineWidth: 2)
                        .frame(width: 20, height: 22)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(port.name)
                    .font(QLTheme.display(18))
                    .foregroundColor(unlocked ? QLTheme.cyanSoft : QLTheme.inkSoft)
                Text(unlocked ? port.tagline
                              : "Unlocks at \(QLCatalog.starsToUnlock(port: port.index)) stars")
                    .font(QLTheme.body(12))
                    .foregroundColor(QLTheme.inkSoft)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(QLTheme.chartGrid).frame(height: 4)
                        Capsule().fill(QLTheme.gold)
                            .frame(width: geo.size.width * CGFloat(stars) / CGFloat(maxStars), height: 4)
                    }
                }
                .frame(height: 4)
            }
            VStack(spacing: 3) {
                Text("\(stars)/\(maxStars)")
                    .font(QLTheme.mono(12))
                    .foregroundColor(QLTheme.cyanSoft)
                QLStarIcon(size: 14, filled: stars > 0)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(QLTheme.cardBG))
        .contentShape(Rectangle())
    }
}

struct QLShiftGridView: View {
    @EnvironmentObject var store: QLStore
    @Environment(\.horizontalSizeClass) private var hSize
    let port: QLPortTemplate

    private let columns = [GridItem(.adaptive(minimum: 74), spacing: 12)]

    var body: some View {
        ZStack {
            QLTheme.chartDeep.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(port.name)
                            .font(QLTheme.display(24))
                            .foregroundColor(QLTheme.cyanSoft)
                        Text(port.tagline)
                            .font(QLTheme.body(13))
                            .foregroundColor(QLTheme.inkSoft)
                    }
                    .padding(.top, 8)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(1...QLCatalog.shiftsPerPort, id: \.self) { shift in
                            shiftTile(shift)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 112)
                .hjColumn(QLLayout.levelGridColumn, hSize)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func shiftTile(_ shift: Int) -> some View {
        let unlocked = store.isShiftUnlocked(port: port.index, shift: shift)
        let record = store.record(port: port.index, shift: shift)
        return Group {
            if unlocked {
                NavigationLink(destination: QLShiftView(port: port.index, shift: shift,
                                                        upgrades: store.upgradeLevels())) {
                    tileBody(shift, unlocked: true, stars: record?.stars ?? 0)
                }
            } else {
                tileBody(shift, unlocked: false, stars: 0)
            }
        }
    }

    private func tileBody(_ shift: Int, unlocked: Bool, stars: Int) -> some View {
        VStack(spacing: 5) {
            if unlocked {
                Text("\(shift)")
                    .font(QLTheme.display(20))
                    .foregroundColor(QLTheme.cyanSoft)
            } else {
                QLLockShape()
                    .stroke(QLTheme.inkSoft, lineWidth: 2)
                    .frame(width: 16, height: 18)
            }
            QLStarsRow(stars: stars, size: 10)
        }
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(unlocked ? QLTheme.cardBG : QLTheme.chartGrid.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(stars == 3 ? QLTheme.gold : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
    }
}
