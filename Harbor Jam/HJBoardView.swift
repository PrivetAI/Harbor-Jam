import SwiftUI

/// Renders the marina board. All geometry is derived from the parent-passed
/// `available` size (never from a Canvas closure's own size).
struct HJBoardView: View {
    @ObservedObject var vm: HJGameViewModel
    var store: HJStore
    var available: CGSize
    @Environment(\.horizontalSizeClass) private var hSize

    private var gridW: Int { vm.state.gridW }
    private var gridH: Int { vm.state.gridH }

    private var cellSize: CGFloat {
        let padding: CGFloat = 12
        let w = max(50, available.width - padding * 2)
        let h = max(50, available.height - padding * 2)
        let fit = min(w / CGFloat(gridW), h / CGFloat(gridH))
        // The cap only exists so a 6x6 harbour on a 12.9" iPad does not draw
        // 149pt cells. It is never consulted on iPhone / compact width, where
        // the largest cell this app can produce is 65pt.
        return HJLayout.wide(hSize) ? min(fit, HJLayout.maxCell) : fit
    }
    private var boardSize: CGSize {
        CGSize(width: cellSize * CGFloat(gridW), height: cellSize * CGFloat(gridH))
    }

    /// How much heavier every hairline in the marina art has to be drawn so it
    /// keeps the weight it was tuned for on a ~350-390pt phone board.
    ///
    /// Hull outlines, bow arrows, current-lane arrows, sandbar wave marks and —
    /// most importantly — the colorblind hull patterns are all specified in
    /// fixed points. Left alone at an 896pt board they would render at roughly
    /// 45% of their phone weight and the accessibility patterns would go from a
    /// readable 3-4 stripes per hull to 9 near-invisible ones.
    ///
    /// Two independent guarantees that this is exactly 1.0 on iPhone:
    ///   * the `wide()` gate returns early on anything that is not a wide iPad;
    ///   * even without it, the widest board an iPhone can produce is
    ///     440 - 24 - 24 = 392pt (16/17 Pro Max, portrait; the board is always
    ///     width-bound there), and 392 / 420 < 1 so `max(1, ...)` pins it to 1.
    /// Note `boardSize` does not depend on `artScale`, so there is no cycle.
    private var artScale: CGFloat {
        guard HJLayout.wide(hSize) else { return 1 }
        return min(max(boardSize.width / HJLayout.artReference, 1), HJLayout.maxArtScale)
    }

    private var waterColor: Color { vm.state.night ? HJTheme.nightWater : HJTheme.seafoam }
    private var frameColor: Color { vm.state.night ? HJTheme.nightBoard : HJTheme.driftwood }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(frameColor)
                .frame(width: boardSize.width + 16, height: boardSize.height + 16)
            RoundedRectangle(cornerRadius: 8)
                .fill(waterColor)
                .frame(width: boardSize.width, height: boardSize.height)

            tileLayer
            currentArrows
            sandbarLayer
            ferryLayer
            boatLayer
        }
        .frame(width: boardSize.width + 16, height: boardSize.height + 16)
        .clipped()
    }

    private var tileLayer: some View {
        ZStack {
            ForEach(0..<gridW, id: \.self) { x in
                Path { p in
                    p.move(to: CGPoint(x: CGFloat(x) * cellSize, y: 0))
                    p.addLine(to: CGPoint(x: CGFloat(x) * cellSize, y: boardSize.height))
                }
                .stroke(Color.white.opacity(vm.state.night ? 0.06 : 0.25), lineWidth: 1 * artScale)
            }
            ForEach(0..<gridH, id: \.self) { y in
                Path { p in
                    p.move(to: CGPoint(x: 0, y: CGFloat(y) * cellSize))
                    p.addLine(to: CGPoint(x: boardSize.width, y: CGFloat(y) * cellSize))
                }
                .stroke(Color.white.opacity(vm.state.night ? 0.06 : 0.25), lineWidth: 1 * artScale)
            }
        }
        .frame(width: boardSize.width, height: boardSize.height)
    }

    private var currentArrows: some View {
        ZStack {
            ForEach(Array(vm.state.currents.enumerated()), id: \.offset) { _, lane in
                if lane.isRow {
                    ForEach(0..<gridW, id: \.self) { x in
                        HJArrowShape(direction: lane.push)
                            .stroke(HJTheme.navy.opacity(0.22), lineWidth: 1.6 * artScale)
                            .frame(width: cellSize * 0.6, height: cellSize * 0.6)
                            .position(cellCenter(x: x, y: lane.index))
                    }
                } else {
                    ForEach(0..<gridH, id: \.self) { y in
                        HJArrowShape(direction: lane.push)
                            .stroke(HJTheme.navy.opacity(0.22), lineWidth: 1.6 * artScale)
                            .frame(width: cellSize * 0.6, height: cellSize * 0.6)
                            .position(cellCenter(x: lane.index, y: y))
                    }
                }
            }
        }
        .frame(width: boardSize.width, height: boardSize.height)
    }

    private var sandbarLayer: some View {
        ZStack {
            ForEach(Array(vm.state.sandbars.enumerated()), id: \.offset) { _, cell in
                let solid = vm.state.tideEnabled && !vm.state.tideHigh
                ZStack {
                    RoundedRectangle(cornerRadius: cellSize * 0.18)
                        .fill(Color(red: 0.90, green: 0.82, blue: 0.62).opacity(solid ? 0.95 : 0.35))
                    if solid {
                        HJWaveShape()
                            .stroke(HJTheme.driftwood.opacity(0.8), lineWidth: 1.4 * artScale)
                            .frame(width: cellSize * 0.55, height: cellSize * 0.3)
                    }
                }
                .frame(width: cellSize * 0.88, height: cellSize * 0.88)
                .position(cellCenter(x: cell.x, y: cell.y))
                .animation(.easeInOut(duration: 0.3), value: vm.state.tideHigh)
            }
        }
        .frame(width: boardSize.width, height: boardSize.height)
    }

    private var ferryLayer: some View {
        ZStack {
            if let f = vm.state.ferry {
                ForEach(0..<f.length, id: \.self) { i in
                    let x = (f.x + i) % gridW
                    RoundedRectangle(cornerRadius: cellSize * 0.12)
                        .fill(Color(red: 0.35, green: 0.35, blue: 0.4))
                        .overlay(
                            Rectangle()
                                .fill(HJTheme.sunGold)
                                .frame(height: cellSize * 0.14)
                                .offset(y: -cellSize * 0.22)
                        )
                        .frame(width: cellSize * 0.94, height: cellSize * 0.7)
                        .position(cellCenter(x: x, y: f.row))
                }
            }
        }
        .frame(width: boardSize.width, height: boardSize.height)
        .animation(.easeInOut(duration: 0.25), value: vm.state.ferry)
    }

    private var boatLayer: some View {
        ZStack {
            ForEach(vm.state.boats) { boat in
                HJBoatView(boat: boat,
                           cellSize: cellSize,
                           anchored: vm.state.isAnchored(boat),
                           shaking: vm.shakeBoatID == boat.id,
                           patterns: store.save.colorblindPatterns,
                           night: vm.state.night,
                           artScale: artScale)
                    .position(boatCenter(boat))
                    .onTapGesture { vm.tapBoat(boat.id, store: store) }
                    .animation(.easeOut(duration: 0.22), value: boat.x)
                    .animation(.easeOut(duration: 0.22), value: boat.y)
            }
        }
        .frame(width: boardSize.width, height: boardSize.height)
    }

    private func cellCenter(x: Int, y: Int) -> CGPoint {
        CGPoint(x: (CGFloat(x) + 0.5) * cellSize, y: (CGFloat(y) + 0.5) * cellSize)
    }

    private func boatCenter(_ boat: HJBoat) -> CGPoint {
        CGPoint(x: (CGFloat(boat.x) + CGFloat(boat.width) / 2) * cellSize,
                y: (CGFloat(boat.y) + CGFloat(boat.height) / 2) * cellSize)
    }
}

struct HJBoatView: View {
    var boat: HJBoat
    var cellSize: CGFloat
    var anchored: Bool
    var shaking: Bool
    var patterns: Bool
    var night: Bool
    /// 1 on iPhone / compact width — see `HJBoardView.artScale`.
    var artScale: CGFloat = 1

    private var hull: Color { HJTheme.hullColors[boat.hullIndex % HJTheme.hullColors.count] }
    private var w: CGFloat { CGFloat(boat.width) * cellSize * 0.92 }
    private var h: CGFloat { CGFloat(boat.height) * cellSize * 0.92 }

    var body: some View {
        ZStack {
            HJHullShape(bow: boat.bow, isBarge: boat.isBarge)
                .fill(hull)
            HJHullShape(bow: boat.bow, isBarge: boat.isBarge)
                .stroke(Color.black.opacity(0.25), lineWidth: 1.5 * artScale)
            if patterns {
                HJPatternOverlay(index: boat.hullIndex, artScale: artScale)
                    .clipShape(HJHullShape(bow: boat.bow, isBarge: boat.isBarge))
            }
            // deck stripe pointing at the bow
            HJArrowShape(direction: boat.bow)
                .stroke(Color.white.opacity(0.85), lineWidth: 2 * artScale)
                .frame(width: min(w, h) * 0.5, height: min(w, h) * 0.5)
            if anchored {
                Circle()
                    .fill(HJTheme.buoyRed)
                    .frame(width: cellSize * 0.3, height: cellSize * 0.3)
                    .overlay(
                        HJLockShape()
                            .stroke(Color.white, lineWidth: 1.4 * artScale)
                            .frame(width: cellSize * 0.18, height: cellSize * 0.18)
                    )
                    .offset(x: w * 0.28, y: -h * 0.28)
            }
        }
        .frame(width: w, height: h)
        // The "blocked" shake is the only feedback for an illegal tap; 4pt of
        // travel is invisible against a 900pt board, so it scales too.
        .offset(x: shaking ? 4 * artScale : 0)
        .animation(shaking ? .easeInOut(duration: 0.08).repeatCount(4, autoreverses: true) : .default, value: shaking)
        .opacity(anchored ? 0.82 : 1)
    }
}

/// Rounded hull with a pointed bow on the bow side.
struct HJHullShape: Shape {
    var bow: HJDirection
    var isBarge: Bool

    func path(in rect: CGRect) -> Path {
        if isBarge {
            var p = Path()
            p.addRoundedRect(in: rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04),
                             cornerSize: CGSize(width: rect.width * 0.14, height: rect.width * 0.14))
            return p
        }
        // Build pointing East, then rotate.
        let local = CGRect(x: 0, y: 0,
                           width: bow.isHorizontal ? rect.width : rect.height,
                           height: bow.isHorizontal ? rect.height : rect.width)
        var p = Path()
        let r = local.height * 0.28
        let bowLen = min(local.width * 0.28, local.height * 0.8)
        p.move(to: CGPoint(x: local.minX + r, y: local.minY))
        p.addLine(to: CGPoint(x: local.maxX - bowLen, y: local.minY))
        p.addQuadCurve(to: CGPoint(x: local.maxX, y: local.midY),
                       control: CGPoint(x: local.maxX - bowLen * 0.15, y: local.minY + local.height * 0.12))
        p.addQuadCurve(to: CGPoint(x: local.maxX - bowLen, y: local.maxY),
                       control: CGPoint(x: local.maxX - bowLen * 0.15, y: local.maxY - local.height * 0.12))
        p.addLine(to: CGPoint(x: local.minX + r, y: local.maxY))
        p.addQuadCurve(to: CGPoint(x: local.minX, y: local.maxY - r),
                       control: CGPoint(x: local.minX, y: local.maxY))
        p.addLine(to: CGPoint(x: local.minX, y: local.minY + r))
        p.addQuadCurve(to: CGPoint(x: local.minX + r, y: local.minY),
                       control: CGPoint(x: local.minX, y: local.minY))
        p.closeSubpath()

        let angle: CGFloat
        switch bow {
        case .east: angle = 0
        case .south: angle = .pi / 2
        case .west: angle = .pi
        case .north: angle = -.pi / 2
        }
        var t = CGAffineTransform.identity
        t = t.translatedBy(x: rect.midX, y: rect.midY)
        t = t.rotated(by: angle)
        t = t.translatedBy(x: -local.midX, y: -local.midY)
        return p.applying(t)
    }
}

struct HJPatternOverlay: View {
    var index: Int
    /// 1 on iPhone / compact width — see `HJBoardView.artScale`.
    ///
    /// Both the stroke weight AND the repeat pitch scale. Scaling only the
    /// stroke would leave a 2.1x iPad hull carrying ~9 stripes where the phone
    /// shows ~3, which reads as a flat wash rather than a distinguishable
    /// pattern — i.e. it would defeat the colorblind setting a different way.
    var artScale: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let s = artScale
            switch index % 4 {
            case 0:
                Path { p in
                    var x: CGFloat = -h
                    while x < w + h {
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x + h, y: h))
                        x += 10 * s
                    }
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 2 * s)
            case 1:
                Path { p in
                    var y: CGFloat = 4 * s
                    while y < h {
                        var x: CGFloat = 4 * s
                        while x < w {
                            p.addEllipse(in: CGRect(x: x, y: y, width: 3 * s, height: 3 * s))
                            x += 9 * s
                        }
                        y += 9 * s
                    }
                }
                .fill(Color.white.opacity(0.4))
            case 2:
                Path { p in
                    var y: CGFloat = 3 * s
                    while y < h {
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                        y += 8 * s
                    }
                }
                .stroke(Color.white.opacity(0.3), lineWidth: 1.6 * s)
            default:
                // 8 hull colors fold onto this 4-way switch, so every branch has to draw
                // something — an empty one leaves two hull colors unmarked and silently
                // defeats the colorblind setting for them.
                Path { p in
                    var x: CGFloat = -h
                    while x < w + h {
                        p.move(to: CGPoint(x: x, y: h))
                        p.addLine(to: CGPoint(x: x + h, y: 0))
                        x += 10 * s
                    }
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 2 * s)
            }
        }
    }
}
