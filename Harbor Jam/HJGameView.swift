import SwiftUI

struct HJGameView: View {
    @EnvironmentObject var store: HJStore
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var vm: HJGameViewModel
    var title: String
    var onNext: (() -> HJGameMode?)?

    @State private var nextMode: HJGameMode? = nil

    init?(mode: HJGameMode, store: HJStore, title: String, onNext: (() -> HJGameMode?)? = nil) {
        guard let model = HJGameViewModel(mode: mode, store: store) else { return nil }
        _vm = StateObject(wrappedValue: model)
        self.title = title
        self.onNext = onNext
    }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 620
            ZStack {
                HJTheme.cream.ignoresSafeArea()
                VStack(spacing: compact ? 6 : 12) {
                    header
                    hudRow
                    HJBoardView(vm: vm, store: store,
                                available: CGSize(width: geo.size.width,
                                                  height: geo.size.height - (compact ? 170 : 210)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    controls
                        .padding(.bottom, compact ? 6 : 12)
                }
                .padding(.horizontal, 12)

                if vm.won {
                    winOverlay
                }
                if !store.save.onboardingSeen {
                    HJOnboardingOverlay()
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack {
            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                HJChevronShape(pointsRight: false)
                    .stroke(HJTheme.navy, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 18)
                    .padding(10)
                    .background(Circle().fill(HJTheme.cardBG))
            }
            Spacer()
            Text(title)
                .font(HJTheme.display(20))
                .foregroundColor(HJTheme.navy)
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.top, 6)
    }

    private var hudRow: some View {
        HStack(spacing: 8) {
            hudChip(label: "MOVES", value: "\(vm.state.taps)/\(vm.par)")
            hudChip(label: "BOATS", value: "\(vm.boatsRemaining)/\(vm.totalBoats)")
            if vm.state.tideEnabled {
                tideChip
            }
            if vm.initialState.tugTokens > 0 {
                tugChip
            }
        }
    }

    private func hudChip(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(HJTheme.body(9, weight: .bold))
                .foregroundColor(HJTheme.inkSoft)
            Text(value)
                .font(HJTheme.mono(15))
                .foregroundColor(HJTheme.navy)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(HJTheme.cardBG))
    }

    private var tideChip: some View {
        VStack(spacing: 2) {
            Text(vm.state.tideHigh ? "HIGH TIDE" : "LOW TIDE")
                .font(HJTheme.body(9, weight: .bold))
                .foregroundColor(vm.state.tideHigh ? HJTheme.navy.opacity(0.6) : HJTheme.buoyRed)
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < (vm.state.taps % 3) ? HJTheme.navy : HJTheme.navy.opacity(0.2))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(HJTheme.cardBG))
    }

    private var tugChip: some View {
        Button(action: { if vm.state.tugTokens > 0 { vm.tugArmed.toggle() } }) {
            VStack(spacing: 2) {
                Text("TUG ×\(vm.state.tugTokens)")
                    .font(HJTheme.body(9, weight: .bold))
                    .foregroundColor(vm.tugArmed ? .white : HJTheme.inkSoft)
                HJTugShape()
                    .stroke(vm.tugArmed ? Color.white : HJTheme.navy,
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(width: 16, height: 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(vm.tugArmed ? HJTheme.navy : HJTheme.cardBG))
        }
        .disabled(vm.state.tugTokens == 0)
        .opacity(vm.state.tugTokens == 0 ? 0.45 : 1)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            controlButton(disabled: !vm.canUndo, action: vm.undo) {
                HJUndoShape()
                    .stroke(HJTheme.navy, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
            controlButton(disabled: vm.won, action: vm.restart) {
                HJRestartShape()
                    .stroke(HJTheme.navy, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func controlButton<S: View>(disabled: Bool, action: @escaping () -> Void, @ViewBuilder icon: () -> S) -> some View {
        Button(action: action) {
            icon()
                .frame(width: 22, height: 22)
                .padding(14)
                .background(Circle().fill(HJTheme.cardBG))
                .overlay(Circle().stroke(HJTheme.navy.opacity(0.15), lineWidth: 1))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    private var winOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Harbor Cleared!")
                    .font(HJTheme.display(26))
                    .foregroundColor(HJTheme.navy)
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { i in
                        HJStarIcon(size: 34, filled: i < vm.earnedStars)
                    }
                }
                VStack(spacing: 4) {
                    Text("Moves: \(vm.state.taps)   Par: \(vm.par)")
                        .font(HJTheme.mono(15))
                        .foregroundColor(HJTheme.navy)
                    if vm.undosUsed == 0 {
                        Text("Flawless — no undo used")
                            .font(HJTheme.body(12, weight: .semibold))
                            .foregroundColor(HJTheme.inkSoft)
                    }
                }
                ForEach(store.recentlyUnlocked, id: \.self) { id in
                    if let a = HJAchievements.all.first(where: { $0.id == id }) {
                        HStack(spacing: 8) {
                            HJTrophyShape().fill(HJTheme.sunGold).frame(width: 16, height: 16)
                            Text(a.title)
                                .font(HJTheme.body(12, weight: .bold))
                                .foregroundColor(HJTheme.navy)
                        }
                    }
                }
                HStack(spacing: 12) {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Text("Back")
                            .font(HJTheme.body(15, weight: .bold))
                            .foregroundColor(HJTheme.navy)
                            .padding(.horizontal, 26).padding(.vertical, 12)
                            .background(Capsule().stroke(HJTheme.navy, lineWidth: 1.6))
                    }
                    if onNext != nil {
                        Button(action: {
                            store.recentlyUnlocked = []
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Text("Continue")
                                .font(HJTheme.body(15, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 26).padding(.vertical, 12)
                                .background(Capsule().fill(HJTheme.navy))
                        }
                    }
                }
            }
            .padding(26)
            .background(RoundedRectangle(cornerRadius: 20).fill(HJTheme.cream))
            .padding(.horizontal, 30)
        }
        .onDisappear { store.recentlyUnlocked = [] }
    }
}

struct HJOnboardingOverlay: View {
    @EnvironmentObject var store: HJStore
    @State private var step = 0

    private let steps: [(String, String)] = [
        ("Tap a Boat", "Tap any boat and it sails straight ahead in the direction of its bow. If the water is clear all the way, it leaves the harbor."),
        ("Blocked Paths", "A boat blocked by another slides up to it and bumps. Clear the way first — order is everything."),
        ("Stars and Par", "Clear every boat. Match par for 3 stars. Undo and restart are always free."),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(steps[step].0)
                    .font(HJTheme.display(22))
                    .foregroundColor(HJTheme.navy)
                Text(steps[step].1)
                    .font(HJTheme.body(14))
                    .foregroundColor(HJTheme.navy.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == step ? HJTheme.navy : HJTheme.navy.opacity(0.25))
                            .frame(width: 8, height: 8)
                    }
                }
                HStack(spacing: 12) {
                    Button(action: finish) {
                        Text("Skip")
                            .font(HJTheme.body(14, weight: .semibold))
                            .foregroundColor(HJTheme.inkSoft)
                    }
                    Spacer()
                    Button(action: {
                        if step < steps.count - 1 { step += 1 } else { finish() }
                    }) {
                        Text(step < steps.count - 1 ? "Next" : "Set Sail")
                            .font(HJTheme.body(15, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24).padding(.vertical, 11)
                            .background(Capsule().fill(HJTheme.navy))
                    }
                }
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 20).fill(HJTheme.cream))
            .padding(.horizontal, 34)
        }
    }

    private func finish() {
        store.save.onboardingSeen = true
        store.persist()
    }
}
