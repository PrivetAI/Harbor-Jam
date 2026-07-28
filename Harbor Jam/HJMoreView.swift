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
            HJTheme.cream.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text("More")
                        .font(HJTheme.display(28))
                        .foregroundColor(HJTheme.navy)
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
            toggleRow("Colorblind boat patterns", isOn: Binding(
                get: { store.save.colorblindPatterns },
                set: { store.save.colorblindPatterns = $0; store.persist() }))

            Button(action: { activeSheet = .privacy }) {
                HStack {
                    Text("Privacy Policy")
                        .font(HJTheme.body(14, weight: .semibold))
                        .foregroundColor(HJTheme.navy)
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
                        .foregroundColor(HJTheme.buoyRed)
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
                .foregroundColor(HJTheme.navy)
            Spacer()
            Button(action: { isOn.wrappedValue.toggle() }) {
                ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn.wrappedValue ? HJTheme.navy : HJTheme.navy.opacity(0.18))
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
                .foregroundColor(HJTheme.navy)
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private var codexCard: some View {
        VStack(spacing: 12) {
            sectionHeader("Harbor Manual")
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
        codexEntry(title: "Boats & Bows",
                   text: "Every boat sails only forward, in the direction of its pointed bow. A clear line to the edge means it exits for good. Blocked boats bump and wait.") {
            AnyView(HJArrowShape(direction: .east)
                .stroke(HJTheme.navy, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 26, height: 26))
        }
        codexEntry(title: "Currents",
                   text: "Arrow lanes mark flowing water. A boat that ends its slide inside a lane is pushed one cell sideways — plan around the drift, or use it as a shortcut.") {
            AnyView(HJWaveShape()
                .stroke(HJTheme.navy, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 26, height: 16))
        }
        codexEntry(title: "Tides",
                   text: "The tide turns every 3 moves. At low tide, sandy shallows harden into solid bars no hull can cross. At high tide they flood over and open up.") {
            AnyView(HJPulseShape()
                .stroke(HJTheme.navy, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 26, height: 18))
        }
        codexEntry(title: "The Ferry",
                   text: "The grey ferry crosses its row on a fixed schedule, advancing after each of your moves and wrapping around. It never stops for anyone — time your crossings.") {
            AnyView(Rectangle()
                .fill(HJTheme.navy.opacity(0.7))
                .frame(width: 26, height: 12)
                .cornerRadius(3))
        }
        codexEntry(title: "Buoy Chains",
                   text: "A boat wearing a red buoy is anchored in place. Its key boat — somewhere in the harbor — must exit first to cast it loose.") {
            AnyView(Circle()
                .fill(HJTheme.buoyRed)
                .frame(width: 18, height: 18))
        }
        codexEntry(title: "Turning Basins",
                   text: "A boat that noses into a turning basin stops there and comes about, bow reversed. It is the only way to send a hull back the way it came — park it clear of a lane now, come back for it later.") {
            AnyView(HJTugShape()
                .stroke(HJTheme.navy, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 22, height: 22))
        }
        codexEntry(title: "Barges",
                   text: "Wide 2×2 barges shrug off currents entirely and block them for others. Slow to place, mighty to move.") {
            AnyView(RoundedRectangle(cornerRadius: 4)
                .fill(HJTheme.driftwood)
                .frame(width: 20, height: 20))
        }
    }

    private func codexEntry(title: String, text: String, @ViewBuilder icon: () -> AnyView) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(HJTheme.seafoam.opacity(0.5))
                    .frame(width: 44, height: 44)
                icon()
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(HJTheme.body(14, weight: .bold))
                    .foregroundColor(HJTheme.navy)
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
                .stroke(HJTheme.navy.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 40, height: 20)
            Text("Harbor Jam")
                .font(HJTheme.display(15))
                .foregroundColor(HJTheme.navy)
            Text("Version 1.0")
                .font(HJTheme.body(11))
                .foregroundColor(HJTheme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 16).fill(HJTheme.cardBG))
    }
}
