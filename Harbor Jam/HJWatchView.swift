import SwiftUI

struct HJWatchView: View {
    @EnvironmentObject var store: HJStore
    @State private var running = false

    var body: some View {
        ZStack {
            HJTheme.chartDeep.ignoresSafeArea()
            if running {
                HJWatchRunView(onEnd: { tons in
                    store.reportWatchRun(tons: tons)
                    running = false
                })
            } else {
                intro
            }
        }
        .navigationBarHidden(true)
    }

    private var intro: some View {
        VStack(spacing: 18) {
            Spacer()
            HJSprite.compassRose.image
                .resizable().scaledToFit()
                .frame(width: 120)
                .opacity(0.5)
            Text("The Watch")
                .font(HJTheme.display(30))
                .foregroundColor(HJTheme.cyanSoft)
            Text("One harbour. The traffic never stops, and it never slows down.\nEvery 90 seconds you pick one upgrade for this run only.")
                .font(HJTheme.body(13))
                .foregroundColor(HJTheme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)

            HStack(spacing: 6) {
                HJSprite.iconTonnage.image
                    .resizable().scaledToFit().frame(width: 18, height: 18)
                Text("Best: \(store.save.watchBestTons) t")
                    .font(HJTheme.mono(15))
                    .foregroundColor(HJTheme.gold)
            }

            Button(action: { running = true }) {
                Text("Stand the watch")
                    .font(HJTheme.body(15, weight: .semibold))
                    .foregroundColor(HJTheme.chartDeep)
                    .padding(.horizontal, 30).padding(.vertical, 13)
                    .background(Capsule().fill(HJTheme.cyan))
                    .contentShape(Rectangle())
            }
            Spacer()
            Spacer().frame(height: 96)
        }
    }
}

private struct HJWatchRunView: View {
    @EnvironmentObject var store: HJStore
    @Environment(\.horizontalSizeClass) private var hSize
    var onEnd: (Int) -> Void

    @StateObject private var vm: HJShiftViewModel
    @State private var upgrades = HJUpgradeLevels.zero
    @State private var offered: [HJUpgradeLine] = []
    @State private var wavesTaken = 0
    @State private var ended = false

    init(onEnd: @escaping (Int) -> Void) {
        self.onEnd = onEnd
        // A fixed seed keeps every run comparable, which is what a leaderboard
        // number has to be. Difficulty comes from the rising stream, not luck.
        let def = HJWatch.shift(seed: 0xB0A7, waves: 40)
        _vm = StateObject(wrappedValue: HJShiftViewModel(def: def, upgrades: .zero))
    }

    private var wave: Int { vm.sim.tick / HJWatch.waveTicks }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 10) {
                    hud.hjColumn(HJLayout.gameChromeColumn, hSize)
                    HJHarborBoardView(vm: vm, screenSize: geo.size)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .coordinateSpace(name: "board")

                if !offered.isEmpty { upgradeOverlay }
                if vm.isOver && !ended { endOverlay }
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .onChange(of: wave) { newWave in
            guard newWave > wavesTaken, !vm.isOver else { return }
            wavesTaken = newWave
            offered = Array(HJUpgradeLine.allCases.shuffled().prefix(3))
            vm.pause()
        }
    }

    private var hud: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                HJSprite.iconTonnage.image
                    .resizable().scaledToFit().frame(width: 16, height: 16)
                Text("\(vm.sim.counters.tonsServed)")
                    .font(HJTheme.mono(14))
                    .foregroundColor(HJTheme.cyanSoft)
            }
            Text("Wave \(wave + 1)")
                .font(HJTheme.body(12, weight: .semibold))
                .foregroundColor(HJTheme.inkSoft)
            Spacer()
            HStack(spacing: 3) {
                ForEach(0..<max(0, vm.sim.reputation), id: \.self) { _ in
                    HJSprite.iconReputation.image
                        .resizable().scaledToFit().frame(width: 16, height: 16)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var upgradeOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Wave \(wave + 1)")
                    .font(HJTheme.display(22))
                    .foregroundColor(HJTheme.cyanSoft)
                Text("Pick one, for this run")
                    .font(HJTheme.body(12))
                    .foregroundColor(HJTheme.inkSoft)
                ForEach(offered) { line in
                    Button(action: { take(line) }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.title)
                                .font(HJTheme.body(14, weight: .semibold))
                                .foregroundColor(HJTheme.cyanSoft)
                            Text(line.detail)
                                .font(HJTheme.body(11))
                                .foregroundColor(HJTheme.inkSoft)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(HJTheme.hullFill))
                        .contentShape(Rectangle())
                    }
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 18).fill(HJTheme.cardBG))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(HJTheme.contour, lineWidth: 1))
            .hjCap(HJLayout.overlayColumn, hSize)
            .padding(.horizontal, 28)
        }
    }

    /// Watch upgrades rebuild the sim's `upgrades` by restarting it? No — the
    /// sim holds `upgrades` immutably, so the levels are tracked here and shown
    /// to the player; they take effect on ships berthed from now on because
    /// `HJSim` reads them at command time.
    private func take(_ line: HJUpgradeLine) {
        switch line {
        case .cranes: upgrades.cranes = min(5, upgrades.cranes + 1)
        case .tugs: upgrades.tugs = min(3, upgrades.tugs + 1)
        case .dredge: upgrades.dredge = min(2, upgrades.dredge + 1)
        case .roadstead: upgrades.roadstead = min(2, upgrades.roadstead + 1)
        case .crew: upgrades.crew = min(2, upgrades.crew + 1)
        }
        vm.applyUpgrades(upgrades)
        offered = []
        vm.resume()
    }

    private var endOverlay: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Watch over")
                    .font(HJTheme.display(24))
                    .foregroundColor(HJTheme.cyanSoft)
                Text("\(vm.sim.counters.tonsServed) t")
                    .font(HJTheme.mono(30, weight: .bold))
                    .foregroundColor(HJTheme.gold)
                Text(vm.sim.counters.tonsServed > store.save.watchBestTons
                     ? "New record" : "Best: \(store.save.watchBestTons) t")
                    .font(HJTheme.body(13))
                    .foregroundColor(HJTheme.inkSoft)
                Text("Waves survived: \(wave + 1)")
                    .font(HJTheme.body(13))
                    .foregroundColor(HJTheme.inkSoft)
                Button(action: {
                    ended = true
                    onEnd(vm.sim.counters.tonsServed)
                }) {
                    Text("Done")
                        .font(HJTheme.body(14, weight: .semibold))
                        .foregroundColor(HJTheme.chartDeep)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 11).fill(HJTheme.cyan))
                        .contentShape(Rectangle())
                }
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 18).fill(HJTheme.cardBG))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(HJTheme.contour, lineWidth: 1))
            .hjCap(HJLayout.overlayColumn, hSize)
            .padding(.horizontal, 28)
        }
    }
}
