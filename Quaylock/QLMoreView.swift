import SwiftUI

struct QLMoreView: View {
    @EnvironmentObject var store: QLStore
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var showResetAlert = false

    var body: some View {
        ZStack {
            QLTheme.chartDeep.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text("More")
                        .font(QLTheme.display(28))
                        .foregroundColor(QLTheme.cyanSoft)
                        .padding(.top, 12)

                    // Toggles keep their label and switch within reach of each
                    // other; only the codex earns the full column.
                    settingsCard
                        .hjCap(QLLayout.panelColumn, hSize)
                    codexCard
                    aboutCard
                        .hjCap(QLLayout.panelColumn, hSize)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .hjColumn(QLLayout.moreColumn, hSize)
            }
        }
        .alert(isPresented: $showResetAlert) {
            Alert(title: Text("Reset Progress?"),
                  message: Text("All stars, records, achievements and stats will be permanently erased."),
                  primaryButton: .destructive(Text("Reset")) { store.resetProgress() },
                  secondaryButton: .cancel())
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 4) {
            sectionHeader("Settings")
            toggleRow("Sound", isOn: Binding(
                get: { store.save.soundOn },
                set: { store.save.soundOn = $0; store.persist() }))
            toggleRow("Haptics", isOn: Binding(
                get: { store.save.hapticsOn },
                set: { store.save.hapticsOn = $0; store.persist() }))
            Button(action: { showResetAlert = true }) {
                HStack {
                    Text("Reset Progress")
                        .font(QLTheme.body(14, weight: .semibold))
                        .foregroundColor(QLTheme.alert)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(QLTheme.cardBG))
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(QLTheme.body(14, weight: .semibold))
                .foregroundColor(QLTheme.cyanSoft)
            Spacer()
            Button(action: { isOn.wrappedValue.toggle() }) {
                ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn.wrappedValue ? QLTheme.cyanSoft : QLTheme.cyanSoft.opacity(0.18))
                        .frame(width: 46, height: 27)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                        .padding(3)
                }
                .animation(.easeInOut(duration: 0.15), value: isOn.wrappedValue)
            }
        }
        .padding(.vertical, 8)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(QLTheme.display(16))
                .foregroundColor(QLTheme.cyanSoft)
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private var codexCard: some View {
        VStack(spacing: 12) {
            sectionHeader("Harbour Manual")
            codexGrid
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(QLTheme.cardBG))
    }

    /// The seven manual entries stack on iPhone (unchanged) and go two-up on a
    /// wide iPad canvas, where a single entry would otherwise be one short line
    /// of text next to a 44pt icon across 780pt.
    @ViewBuilder
    private var codexGrid: some View {
        if QLLayout.wide(hSize) {
            LazyVGrid(columns: QLLayout.twoColumns(spacing: 16), spacing: 14) {
                codexEntries
            }
        } else {
            VStack(spacing: 12) {
                codexEntries
            }
        }
    }

    @ViewBuilder
    private var codexEntries: some View {
        codexEntry(title: "The Quay",
                   text: "A hull needs as many berths in a row as her length. Scatter short ships and the quay fragments: six berths free, none of them adjacent, and the next big hull has nowhere to go.") {
            AnyView(QLSprite.berthCrane.image
                .resizable().scaledToFit().frame(width: 26, height: 30))
        }
        codexEntry(title: "Draft & Depth",
                   text: "The number on a hull is her draft; the number on a berth is the water over it. Draft above depth and she cannot come alongside at all.") {
            AnyView(Text("3")
                .font(QLTheme.mono(18, weight: .bold))
                .foregroundColor(QLTheme.cyanSoft))
        }
        codexEntry(title: "The Tide",
                   text: "Water rises and falls on a fixed cycle — the strip at the top counts down to the turn. Moor a deep hull on the flood and the ebb strands her: she keeps unloading, but she cannot leave, and she keeps every berth she is on.") {
            AnyView(QLSprite.iconTide.image
                .resizable().scaledToFit().frame(width: 26, height: 26))
        }
        codexEntry(title: "The Channel",
                   text: "One ship in the fairway at a time, coming or going. Sending a finished hull out costs you the channel that the next arrival needs — that is the whole decision.") {
            AnyView(QLArrowShape(direction: .north)
                .stroke(QLTheme.cyanSoft, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 24, height: 24))
        }
        codexEntry(title: "Berth Gear",
                   text: "Cranes take containers, conveyors take bulk, pipelines take liquid. Any other berth still works — at two and a half times the unloading time, with your quay tied up for all of it.") {
            AnyView(QLSprite.cargoContainer.image
                .resizable().scaledToFit().frame(width: 26, height: 26))
        }
        codexEntry(title: "Patience",
                   text: "Ships on the roadstead lose patience while they wait, and the roadstead only holds so many. Every ship turned away costs an anchor. Lose them all and the harbour is jammed.") {
            AnyView(QLSprite.iconReputation.image
                .resizable().scaledToFit().frame(width: 24, height: 24))
        }
    }

    private func codexEntry(title: String, text: String, @ViewBuilder icon: () -> AnyView) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(QLTheme.cyan.opacity(0.5))
                    .frame(width: 44, height: 44)
                icon()
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(QLTheme.body(14, weight: .bold))
                    .foregroundColor(QLTheme.cyanSoft)
                Text(text)
                    .font(QLTheme.body(12))
                    .foregroundColor(QLTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var aboutCard: some View {
        VStack(spacing: 6) {
            QLWaveShape()
                .stroke(QLTheme.cyanSoft.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 40, height: 20)
            Text("Quaylock")
                .font(QLTheme.display(15))
                .foregroundColor(QLTheme.cyanSoft)
            Text("Version 1.0")
                .font(QLTheme.body(11))
                .foregroundColor(QLTheme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 16).fill(QLTheme.cardBG))
    }
}
