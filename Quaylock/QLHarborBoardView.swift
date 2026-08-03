import SwiftUI

/// The harbour: quay along the top, water and the channel in the middle, the
/// roadstead queue along the bottom.
///
/// All geometry derives from the parent-passed `screenSize`. Nothing here reads
/// a `Canvas` closure's own `size`, which on iOS is not the parent's size and
/// has silently broken camera maths in this portfolio before.
struct QLHarborBoardView: View {
    @ObservedObject var vm: QLShiftViewModel
    var screenSize: CGSize
    @Environment(\.horizontalSizeClass) private var hSize

    /// Ship being dragged from the roadstead, and where the finger is.
    @State private var draggingShip: Int? = nil
    @State private var dragPoint: CGPoint = .zero

    private var slotCount: Int { vm.sim.def.harbor.slots.count }

    /// Berths never stretch past this. Without a cap, a 12-berth quay on an iPad
    /// gives 100pt cells whose art cannot fill them, and the quay wall visibly
    /// breaks into segments.
    private static let maxSlotWidth: CGFloat = 62

    private var slotWidth: CGFloat {
        let available = min(screenSize.width, QLLayout.wide(hSize) ? QLLayout.boardColumn : screenSize.width) - 24
        return min(available / CGFloat(slotCount), Self.maxSlotWidth)
    }
    private var boardWidth: CGFloat { slotWidth * CGFloat(slotCount) }
    private var quayHeight: CGFloat { min(72, slotWidth * 1.5) }
    private var hullHeight: CGFloat { min(50, slotWidth * 1.05) }

    var body: some View {
        VStack(spacing: 0) {
            // Quay and water share one ZStack so a moored hull can hang below
            // the wall. Drawn inside the quay layer instead, the water layer's
            // opaque background — the next child of the VStack — paints over
            // everything that overflows, and the ships vanish.
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    quayLayer
                    waterLayer
                }
                berthedHulls
            }
            roadsteadLayer
            // Clearance for the floating tab bar. A .safeAreaInset on a stack
            // NavigationView does not reach a pushed screen, so the padding has
            // to live inside the content.
            Spacer(minLength: 96)
        }
        .frame(width: boardWidth)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quay

    private var quayLayer: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(0..<slotCount, id: \.self) { i in
                    berthCell(i)
                        .frame(width: slotWidth, height: quayHeight)
                }
            }
            // One continuous wall across the whole quay, drawn by the view
            // rather than baked into each berth sprite.
            Rectangle()
                .fill(QLTheme.gold)
                .frame(width: boardWidth, height: 5)
        }
        .frame(width: boardWidth, height: quayHeight)
    }

    private func berthCell(_ i: Int) -> some View {
        let slot = vm.sim.def.harbor.slots[i]
        let depth = vm.sim.effectiveDepth(slot: i)
        let closed = vm.sim.isOutOfService(slot: i)
        let highlight = dragHighlight(for: i)
        return ZStack {
            QLSprite.berth(slot.equipment).image
                .resizable()
                .scaledToFit()
                .opacity(closed ? 0.3 : 1)
            if let tint = highlight {
                Rectangle().fill(tint.opacity(0.3))
            }
            // Depth sits at the TOP of the cell: a berthed hull straddles the
            // bottom edge and would cover a label placed there — exactly the
            // number the player needs while deciding where to put her.
            VStack {
                Text("\(depth)")
                    .font(QLTheme.mono(11, weight: .bold))
                    .foregroundColor(depth <= 2 ? QLTheme.warn : QLTheme.cyanSoft.opacity(0.85))
                    .padding(.top, 6)
                Spacer()
            }
            if closed {
                QLCloseShape()
                    .stroke(QLTheme.alert, lineWidth: 2)
                    .frame(width: slotWidth * 0.4, height: slotWidth * 0.4)
            }
        }
    }

    /// Green where the held ship would fit, red where it would not.
    private func dragHighlight(for slot: Int) -> Color? {
        guard let id = draggingShip,
              let ship = vm.sim.ships.first(where: { $0.id == id }) else { return nil }
        guard slot + ship.length <= slotCount else { return nil }
        let target = targetSlot(for: dragPoint, length: ship.length)
        guard slot >= target, slot < target + ship.length else { return nil }
        return vm.canBerth(shipID: id, atSlot: target) == .none ? QLTheme.success : QLTheme.alert
    }

    private var berthedHulls: some View {
        ForEach(vm.sim.ships.filter { $0.holdsBerth }) { ship in
            hullView(ship, width: slotWidth * CGFloat(ship.length))
                .frame(width: slotWidth * CGFloat(ship.length), height: hullHeight)
                // Moored alongside, just under the wall — not straddling it.
                // Straddling buried the upper half of every hull behind the
                // berth art, hiding the cargo mark and the draft.
                .offset(x: CGFloat(ship.berthStart ?? 0) * slotWidth,
                        y: quayHeight - hullHeight * 0.12)
                .opacity(ship.state == .transitingIn ? 0.45 : 1)
                .onTapGesture {
                    if ship.state == .berthed && ship.unloadLeft <= 0 { vm.send(shipID: ship.id) }
                }
                .animation(.easeOut(duration: 0.2), value: ship.state)
        }
    }

    // MARK: - Water

    private var waterLayer: some View {
        ZStack {
            QLSprite.depthContours.image
                .resizable()
                .scaledToFill()
                .opacity(0.14)
                .clipped()

            QLSprite.compassRose.image
                .resizable()
                .scaledToFit()
                .frame(width: boardWidth * 0.3)
                .opacity(0.1)
                .offset(x: boardWidth * 0.3, y: -20)

            channel

            QLSprite.buoyPort.image
                .resizable().scaledToFit().frame(width: 18)
                .offset(x: -slotWidth * 1.1, y: -18)
            QLSprite.buoyStarboard.image
                .resizable().scaledToFit().frame(width: 18)
                .offset(x: slotWidth * 1.1, y: 26)

            transitingHulls
        }
        .frame(width: boardWidth, height: waterHeight)
        .background(QLTheme.chartDeep)
    }

    /// The water takes whatever the quay, the roadstead and the chrome leave.
    /// Derived from the parent-passed height, never from a child geometry read.
    private var waterHeight: CGFloat {
        max(150, screenSize.height - quayHeight - roadsteadHeight - 260)
    }

    private var roadsteadHeight: CGFloat { 116 }

    private var channel: some View {
        ZStack {
            Rectangle()
                .fill(vm.sim.channelBusy ? QLTheme.cyan.opacity(0.12) : Color.clear)
                .frame(width: slotWidth * 1.6)
            HStack(spacing: slotWidth * 1.6) {
                dashedEdge
                dashedEdge
            }
        }
    }

    private var dashedEdge: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 1, height: waterHeight)
            .overlay(
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                    .foregroundColor(QLTheme.contour)
            )
    }

    /// Hulls under way sit in the channel. Inbound rides up from the roadstead,
    /// outbound rides back down, so the shared lane is visibly one at a time.
    private var transitingHulls: some View {
        ForEach(vm.sim.ships.filter { $0.state == .transitingIn || $0.state == .transitingOut }) { ship in
            hullView(ship, width: slotWidth * CGFloat(ship.length))
                .frame(width: slotWidth * CGFloat(ship.length), height: hullHeight)
                .rotationEffect(.degrees(-90))
                .offset(y: ship.state == .transitingIn ? -10 : 20)
                .opacity(0.85)
        }
    }

    // MARK: - Roadstead

    private var roadsteadLayer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Roadstead")
                    .font(QLTheme.body(11, weight: .semibold))
                    .foregroundColor(QLTheme.cyanSoft.opacity(0.6))
                Spacer()
                Text("\(vm.sim.waitingShips.count)/\(vm.sim.roadsteadCapacity)")
                    .font(QLTheme.mono(11))
                    .foregroundColor(QLTheme.cyanSoft.opacity(0.6))
            }
            // Six waiting ships at full card width overflow the board, and the
            // sixth is the one about to be lost — it must stay reachable.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(vm.sim.waitingShips) { ship in
                        roadsteadCard(ship)
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(height: roadsteadHeight - 26)
        }
        .padding(.top, 10)
        .frame(width: boardWidth, height: roadsteadHeight, alignment: .topLeading)
    }

    private func roadsteadCard(_ ship: QLShip) -> some View {
        let cardW = max(58, min(slotWidth * CGFloat(ship.length) * 0.9, 108))
        let dragging = draggingShip == ship.id
        return VStack(spacing: 5) {
            hullView(ship, width: cardW)
                .frame(width: cardW, height: 38)
            patienceBar(ship)
                .frame(width: cardW, height: 5)
            Text("L\(ship.length) · D\(ship.draft)")
                .font(QLTheme.mono(10))
                .foregroundColor(QLTheme.cyanSoft.opacity(0.75))
        }
        // The tap target must be established BEFORE any offset, and this view is
        // never `.position()`ed — a contentShape applied after positioning
        // becomes a screen-sized target that eats every control beneath it.
        .contentShape(Rectangle())
        .opacity(dragging ? 0.35 : 1)
        .gesture(
            DragGesture(coordinateSpace: .named("board"))
                .onChanged { g in
                    draggingShip = ship.id
                    dragPoint = g.location
                }
                .onEnded { g in
                    let target = targetSlot(for: g.location, length: ship.length)
                    vm.tryBerth(shipID: ship.id, atSlot: target)
                    draggingShip = nil
                }
        )
    }

    private func patienceBar(_ ship: QLShip) -> some View {
        let frac = ship.patienceTicks == 0 ? 0
            : max(0, min(1, Double(ship.patienceLeft) / Double(ship.patienceTicks)))
        let color: Color = frac > 0.5 ? QLTheme.success : (frac > 0.25 ? QLTheme.warn : QLTheme.alert)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(QLTheme.chartGrid)
                Capsule().fill(color).frame(width: geo.size.width * CGFloat(frac))
            }
        }
    }

    // MARK: - Shared pieces

    private func hullView(_ ship: QLShip, width: CGFloat) -> some View {
        ZStack {
            QLSprite.hull(length: ship.length).image
                .resizable()
                .scaledToFit()
            QLSprite.cargo(ship.cargo).image
                .resizable()
                .scaledToFit()
                .frame(width: width * 0.22)
                .offset(x: -width * 0.28)
            // Clear of the bow chevron, which the hull art puts at +0.05…+0.11
            // of the width from centre.
            Text("\(ship.draft)")
                .font(QLTheme.mono(11, weight: .bold))
                .foregroundColor(QLTheme.cyanSoft)
                .offset(x: -width * 0.08)
            if ship.state == .aground {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(QLTheme.alert, lineWidth: 2)
            }
            if ship.state == .berthed && ship.unloadLeft <= 0 {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(QLTheme.gold, lineWidth: 2)
            }
            if ship.isVIP {
                Circle()
                    .fill(QLTheme.gold)
                    .frame(width: 7, height: 7)
                    .offset(x: width * 0.34, y: -12)
            }
        }
    }

    /// Which berth a drop at `point` aims at. Clamped so a drop near either end
    /// of the quay still names a legal starting slot for this hull's length.
    private func targetSlot(for point: CGPoint, length: Int) -> Int {
        let raw = Int((point.x - slotWidth * CGFloat(length) / 2) / slotWidth + 0.5)
        return max(0, min(slotCount - length, raw))
    }
}
