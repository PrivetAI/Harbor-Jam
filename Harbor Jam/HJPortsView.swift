import SwiftUI

struct HJPortsView: View {
    @EnvironmentObject var store: HJStore
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        ZStack {
            HJTheme.chartDeep.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    shipyardBar
                    ForEach(HJCatalog.ports, id: \.index) { port in
                        portCard(port)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 112)
                .hjColumn(HJLayout.harborColumn, hSize)
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Harbor Jam")
                    .font(HJTheme.display(30))
                    .foregroundColor(HJTheme.cyanSoft)
                Text("Berth them, work them, get them out")
                    .font(HJTheme.body(13))
                    .foregroundColor(HJTheme.inkSoft)
            }
            Spacer()
            VStack(spacing: 2) {
                HJStarIcon(size: 20, filled: true)
                Text("\(store.totalStars())")
                    .font(HJTheme.mono(15))
                    .foregroundColor(HJTheme.cyanSoft)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(HJTheme.cardBG))
        }
        .padding(.top, 10)
    }

    private var shipyardBar: some View {
        NavigationLink(destination: HJShipyardView()) {
            HStack {
                HJSprite.iconCoin.image
                    .resizable().scaledToFit().frame(width: 20, height: 20)
                Text("\(store.save.coins)")
                    .font(HJTheme.mono(15))
                    .foregroundColor(HJTheme.gold)
                Spacer()
                Text("Shipyard")
                    .font(HJTheme.body(14, weight: .semibold))
                    .foregroundColor(HJTheme.cyanSoft)
                HJChevronShape()
                    .stroke(HJTheme.cyan, lineWidth: 2)
                    .frame(width: 8, height: 13)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(HJTheme.cardBG))
            .contentShape(Rectangle())
        }
    }

    private func portCard(_ port: HJPortTemplate) -> some View {
        let unlocked = store.isPortUnlocked(port.index)
        let stars = store.portStars(port.index)
        let maxStars = HJCatalog.shiftsPerPort * 3
        return Group {
            if unlocked {
                NavigationLink(destination: HJShiftGridView(port: port)) {
                    portCardBody(port, unlocked: true, stars: stars, maxStars: maxStars)
                }
            } else {
                portCardBody(port, unlocked: false, stars: stars, maxStars: maxStars)
            }
        }
    }

    private func portCardBody(_ port: HJPortTemplate, unlocked: Bool,
                              stars: Int, maxStars: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(unlocked ? HJTheme.hullFill : HJTheme.chartGrid)
                    .frame(width: 54, height: 54)
                if unlocked {
                    HJWaveShape()
                        .stroke(HJTheme.cyan, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .frame(width: 28, height: 18)
                } else {
                    HJLockShape()
                        .stroke(HJTheme.inkSoft, lineWidth: 2)
                        .frame(width: 20, height: 22)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(port.name)
                    .font(HJTheme.display(18))
                    .foregroundColor(unlocked ? HJTheme.cyanSoft : HJTheme.inkSoft)
                Text(unlocked ? port.tagline
                              : "Unlocks at \(HJCatalog.starsToUnlock(port: port.index)) stars")
                    .font(HJTheme.body(12))
                    .foregroundColor(HJTheme.inkSoft)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(HJTheme.chartGrid).frame(height: 4)
                        Capsule().fill(HJTheme.gold)
                            .frame(width: geo.size.width * CGFloat(stars) / CGFloat(maxStars), height: 4)
                    }
                }
                .frame(height: 4)
            }
            VStack(spacing: 3) {
                Text("\(stars)/\(maxStars)")
                    .font(HJTheme.mono(12))
                    .foregroundColor(HJTheme.cyanSoft)
                HJStarIcon(size: 14, filled: stars > 0)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(HJTheme.cardBG))
        .contentShape(Rectangle())
    }
}

struct HJShiftGridView: View {
    @EnvironmentObject var store: HJStore
    @Environment(\.horizontalSizeClass) private var hSize
    let port: HJPortTemplate

    private let columns = [GridItem(.adaptive(minimum: 74), spacing: 12)]

    var body: some View {
        ZStack {
            HJTheme.chartDeep.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(port.name)
                            .font(HJTheme.display(24))
                            .foregroundColor(HJTheme.cyanSoft)
                        Text(port.tagline)
                            .font(HJTheme.body(13))
                            .foregroundColor(HJTheme.inkSoft)
                    }
                    .padding(.top, 8)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(1...HJCatalog.shiftsPerPort, id: \.self) { shift in
                            shiftTile(shift)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 112)
                .hjColumn(HJLayout.levelGridColumn, hSize)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func shiftTile(_ shift: Int) -> some View {
        let unlocked = store.isShiftUnlocked(port: port.index, shift: shift)
        let record = store.record(port: port.index, shift: shift)
        return Group {
            if unlocked {
                NavigationLink(destination: HJShiftView(port: port.index, shift: shift,
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
                    .font(HJTheme.display(20))
                    .foregroundColor(HJTheme.cyanSoft)
            } else {
                HJLockShape()
                    .stroke(HJTheme.inkSoft, lineWidth: 2)
                    .frame(width: 16, height: 18)
            }
            HJStarsRow(stars: stars, size: 10)
        }
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(unlocked ? HJTheme.cardBG : HJTheme.chartGrid.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(stars == 3 ? HJTheme.gold : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
    }
}
