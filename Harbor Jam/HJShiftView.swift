import SwiftUI

struct HJShiftView: View {
    @EnvironmentObject var store: HJStore
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.horizontalSizeClass) private var hSize

    let port: Int
    let shift: Int

    @StateObject private var vm: HJShiftViewModel
    @State private var reported = false
    @State private var showPause = false
    @State private var onboardingStep = 0

    init(port: Int, shift: Int, upgrades: HJUpgradeLevels) {
        self.port = port
        self.shift = shift
        let def = HJCatalog.shift(port: port, shift: shift) ?? HJShiftDef(
            port: port, shift: shift,
            harbor: HJHarborDef(slots: [], channelTransitTicks: 1, tideAmplitude: 0,
                                tideStepTicks: 0, roadsteadCapacity: 4),
            arrivals: [], outages: [], storms: [],
            parTicks: 1, target2: 0, target3: 0)
        _vm = StateObject(wrappedValue: HJShiftViewModel(def: def, upgrades: upgrades))
    }

    private var isOnboarding: Bool {
        !store.save.onboardingSeen && port == 1 && shift == 1
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                HJTheme.chartDeep.ignoresSafeArea()

                VStack(spacing: 10) {
                    hud
                        .hjColumn(HJLayout.gameChromeColumn, hSize)
                    if vm.sim.def.harbor.tideAmplitude > 0 {
                        tideStrip
                            .hjColumn(HJLayout.gameChromeColumn, hSize)
                    }
                    HJHarborBoardView(vm: vm, screenSize: geo.size)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .coordinateSpace(name: "board")

                if let flash = vm.lastRefusal, !flash.message.isEmpty {
                    refusalToast(flash)
                }

                // Overlays are ZStack siblings, never `.sheet`: iOS 15 honours
                // only the LAST `.sheet` attached to a view, and this screen
                // needs three of them.
                if showPause { pauseOverlay }
                if vm.isOver && vm.isFailed { failedOverlay }
                if vm.isOver && !vm.isFailed { completeOverlay }
                if isOnboarding && !vm.isOver { onboardingChip }
            }
        }
        .navigationBarHidden(true)
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    // MARK: - HUD

    private var hud: some View {
        HStack(spacing: 14) {
            Button(action: { showPause = true; vm.pause() }) {
                HJPauseShape()
                    .fill(HJTheme.cyan)
                    .frame(width: 16, height: 18)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }

            hudStat(HJSprite.iconTonnage, "\(vm.sim.counters.tonsServed)")
            hudStat(HJSprite.iconCoin, "\(vm.sim.counters.revenue)")

            Spacer()

            HStack(spacing: 3) {
                ForEach(0..<max(0, vm.sim.reputation), id: \.self) { _ in
                    HJSprite.iconReputation.image
                        .resizable().scaledToFit().frame(width: 16, height: 16)
                }
            }
            Text("\(vm.sim.counters.shipsServed)/\(vm.sim.totalShips)")
                .font(HJTheme.mono(12))
                .foregroundColor(HJTheme.cyanSoft.opacity(0.8))
        }
        .padding(.horizontal, 4)
    }

    private func hudStat(_ sprite: HJSprite, _ value: String) -> some View {
        HStack(spacing: 4) {
            sprite.image.resizable().scaledToFit().frame(width: 16, height: 16)
            Text(value)
                .font(HJTheme.mono(13))
                .foregroundColor(HJTheme.cyanSoft)
        }
    }

    // MARK: - Tide

    private var tideStrip: some View {
        let amp = vm.sim.def.harbor.tideAmplitude
        let offset = vm.sim.tideOffset
        let toTurn = vm.sim.ticksToTideTurn()
        let rising = vm.sim.tideOffset(at: vm.sim.tick + 1) >= offset
        return HStack(spacing: 8) {
            HJSprite.iconTide.image.resizable().scaledToFit().frame(width: 16, height: 16)
            HStack(spacing: 3) {
                ForEach(-amp...amp, id: \.self) { level in
                    Capsule()
                        .fill(level <= offset ? HJTheme.cyan : HJTheme.chartGrid)
                        .frame(width: 16, height: 6)
                }
            }
            HJArrowShape(direction: rising ? .north : .south)
                .stroke(rising ? HJTheme.cyan : HJTheme.warn, lineWidth: 1.8)
                .frame(width: 14, height: 14)
            Text("\(toTurn / HJTuning.tickHz)s")
                .font(HJTheme.mono(11))
                .foregroundColor(HJTheme.cyanSoft.opacity(0.7))
            Spacer()
            if vm.sim.stormActive {
                Text("STORM")
                    .font(HJTheme.mono(10, weight: .bold))
                    .foregroundColor(HJTheme.alert)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Feedback

    private func refusalToast(_ flash: HJRefusalFlash) -> some View {
        VStack {
            Spacer()
            Text(flash.message)
                .font(HJTheme.body(13, weight: .semibold))
                .foregroundColor(HJTheme.chartDeep)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(HJTheme.warn))
                .padding(.bottom, 190)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Overlays

    private var pauseOverlay: some View {
        overlayCard(title: "Paused") {
            VStack(spacing: 10) {
                overlayButton("Resume") { showPause = false; vm.resume() }
                overlayButton("Quit shift") { presentationMode.wrappedValue.dismiss() }
            }
        }
    }

    private var completeOverlay: some View {
        overlayCard(title: "Shift complete") {
            VStack(spacing: 12) {
                HJStarsRow(stars: vm.stars, size: 26)
                statLine("Score", "\(vm.score)")
                statLine("Two stars at", "\(vm.sim.def.target2)")
                statLine("Three stars at", "\(vm.sim.def.target3)")
                statLine("Revenue", "\(vm.sim.counters.revenue)")
                statLine("Tons", "\(vm.sim.counters.tonsServed)")
                statLine("Turned away", "\(vm.sim.counters.shipsLost)")
                overlayButton("Back to port") { presentationMode.wrappedValue.dismiss() }
            }
        }
        .onAppear {
            guard !reported else { return }
            reported = true
            store.reportShiftWin(port: port, shift: shift, score: vm.score,
                                 stars: vm.stars, counters: vm.sim.counters)
        }
    }

    private var failedOverlay: some View {
        overlayCard(title: "Harbour jammed") {
            VStack(spacing: 12) {
                Text("Reputation ran out — too many ships turned away.")
                    .font(HJTheme.body(13))
                    .foregroundColor(HJTheme.cyanSoft.opacity(0.8))
                    .multilineTextAlignment(.center)
                statLine("Tons moved", "\(vm.sim.counters.tonsServed)")
                statLine("Turned away", "\(vm.sim.counters.shipsLost)")
                overlayButton("Back to port") { presentationMode.wrappedValue.dismiss() }
            }
        }
    }

    private var onboardingChip: some View {
        let steps = [
            "Drag a ship from the roadstead onto free berths.",
            "Deep hulls need deep water — check the number on the berth.",
            "Tap a ship with a gold outline to send her out.",
            "Only one ship fits the channel. Spend it well.",
        ]
        return VStack {
            Spacer()
            VStack(spacing: 8) {
                Text(steps[min(onboardingStep, steps.count - 1)])
                    .font(HJTheme.body(13))
                    .foregroundColor(HJTheme.cyanSoft)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("Skip") {
                        store.save.onboardingSeen = true
                        store.persist()
                    }
                    .font(HJTheme.body(12))
                    .foregroundColor(HJTheme.cyanSoft.opacity(0.6))
                    Button(onboardingStep >= steps.count - 1 ? "Got it" : "Next") {
                        if onboardingStep >= steps.count - 1 {
                            store.save.onboardingSeen = true
                            store.persist()
                        } else {
                            onboardingStep += 1
                        }
                    }
                    .font(HJTheme.body(12, weight: .semibold))
                    .foregroundColor(HJTheme.gold)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(HJTheme.cardBG))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(HJTheme.contour, lineWidth: 1))
            .padding(.horizontal, 24)
            .padding(.bottom, 104)
        }
    }

    private func overlayCard<Content: View>(title: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(title)
                    .font(HJTheme.display(22))
                    .foregroundColor(HJTheme.cyanSoft)
                content()
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 18).fill(HJTheme.cardBG))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(HJTheme.contour, lineWidth: 1))
            .hjCap(HJLayout.overlayColumn, hSize)
            .padding(.horizontal, 28)
        }
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(HJTheme.body(13))
                .foregroundColor(HJTheme.cyanSoft.opacity(0.7))
            Spacer()
            Text(value)
                .font(HJTheme.mono(13))
                .foregroundColor(HJTheme.cyanSoft)
        }
        .frame(minWidth: 200)
    }

    private func overlayButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(HJTheme.body(14, weight: .semibold))
                .foregroundColor(HJTheme.chartDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 11).fill(HJTheme.cyan))
                .contentShape(Rectangle())
        }
    }
}
