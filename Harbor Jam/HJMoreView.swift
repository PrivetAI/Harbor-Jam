import SwiftUI

struct HJMoreView: View {
    @EnvironmentObject var store: HJStore
    @Environment(\.horizontalSizeClass) private var hSize

    enum ActiveSheet: Identifiable {
        case privacy
        var id: Int { 0 }
    }
    @State private var activeSheet: ActiveSheet? = nil
    @State private var showResetAlert = false

    var body: some View {
        ZStack {
            HJTheme.chartDeep.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text("More")
                        .font(HJTheme.display(28))
                        .foregroundColor(HJTheme.cyanSoft)
                        .padding(.top, 12)

                    // Toggles keep their label and switch within reach of each
                    // other; only the codex earns the full column.
                    settingsCard
                        .hjCap(HJLayout.panelColumn, hSize)
                    codexCard
                    aboutCard
                        .hjCap(HJLayout.panelColumn, hSize)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
                .hjColumn(HJLayout.moreColumn, hSize)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .privacy:
                HarborJamWebPanel(urlString: "https://harborjam.org/")
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
            Button(action: { activeSheet = .privacy }) {
                HStack {
                    Text("Privacy Policy")
                        .font(HJTheme.body(14, weight: .semibold))
                        .foregroundColor(HJTheme.cyanSoft)
                    Spacer()
                    HJChevronShape()
                        .stroke(HJTheme.inkSoft, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 12, height: 12)
                }
                .padding(.vertical, 12)
            }

            Button(action: { showResetAlert = true }) {
                HStack {
                    Text("Reset Progress")
                        .font(HJTheme.body(14, weight: .semibold))
                        .foregroundColor(HJTheme.alert)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(HJTheme.cardBG))
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(HJTheme.body(14, weight: .semibold))
                .foregroundColor(HJTheme.cyanSoft)
            Spacer()
            Button(action: { isOn.wrappedValue.toggle() }) {
                ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn.wrappedValue ? HJTheme.cyanSoft : HJTheme.cyanSoft.opacity(0.18))
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
                .font(HJTheme.display(16))
                .foregroundColor(HJTheme.cyanSoft)
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
        .background(RoundedRectangle(cornerRadius: 16).fill(HJTheme.cardBG))
    }

    /// The seven manual entries stack on iPhone (unchanged) and go two-up on a
    /// wide iPad canvas, where a single entry would otherwise be one short line
    /// of text next to a 44pt icon across 780pt.
    @ViewBuilder
    private var codexGrid: some View {
        if HJLayout.wide(hSize) {
            LazyVGrid(columns: HJLayout.twoColumns(spacing: 16), spacing: 14) {
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
            AnyView(HJSprite.berthCrane.image
                .resizable().scaledToFit().frame(width: 26, height: 30))
        }
        codexEntry(title: "Draft & Depth",
                   text: "The number on a hull is her draft; the number on a berth is the water over it. Draft above depth and she cannot come alongside at all.") {
            AnyView(Text("3")
                .font(HJTheme.mono(18, weight: .bold))
                .foregroundColor(HJTheme.cyanSoft))
        }
        codexEntry(title: "The Tide",
                   text: "Water rises and falls on a fixed cycle — the strip at the top counts down to the turn. Moor a deep hull on the flood and the ebb strands her: she keeps unloading, but she cannot leave, and she keeps every berth she is on.") {
            AnyView(HJSprite.iconTide.image
                .resizable().scaledToFit().frame(width: 26, height: 26))
        }
        codexEntry(title: "The Channel",
                   text: "One ship in the fairway at a time, coming or going. Sending a finished hull out costs you the channel that the next arrival needs — that is the whole decision.") {
            AnyView(HJArrowShape(direction: .north)
                .stroke(HJTheme.cyanSoft, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 24, height: 24))
        }
        codexEntry(title: "Berth Gear",
                   text: "Cranes take containers, conveyors take bulk, pipelines take liquid. Any other berth still works — at two and a half times the unloading time, with your quay tied up for all of it.") {
            AnyView(HJSprite.cargoContainer.image
                .resizable().scaledToFit().frame(width: 26, height: 26))
        }
        codexEntry(title: "Patience",
                   text: "Ships on the roadstead lose patience while they wait, and the roadstead only holds so many. Every ship turned away costs an anchor. Lose them all and the harbour is jammed.") {
            AnyView(HJSprite.iconReputation.image
                .resizable().scaledToFit().frame(width: 24, height: 24))
        }
    }

    private func codexEntry(title: String, text: String, @ViewBuilder icon: () -> AnyView) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(HJTheme.cyan.opacity(0.5))
                    .frame(width: 44, height: 44)
                icon()
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(HJTheme.body(14, weight: .bold))
                    .foregroundColor(HJTheme.cyanSoft)
                Text(text)
                    .font(HJTheme.body(12))
                    .foregroundColor(HJTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var aboutCard: some View {
        VStack(spacing: 6) {
            HJWaveShape()
                .stroke(HJTheme.cyanSoft.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 40, height: 20)
            Text("Harbor Jam")
                .font(HJTheme.display(15))
                .foregroundColor(HJTheme.cyanSoft)
            Text("Version 1.0")
                .font(HJTheme.body(11))
                .foregroundColor(HJTheme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 16).fill(HJTheme.cardBG))
    }
}
