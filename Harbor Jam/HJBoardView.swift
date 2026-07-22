import SwiftUI

/// Renders the marina board. All geometry is derived from the parent-passed
/// `available` size (never from a Canvas closure's own size).
struct HJBoardView: View {
    @ObservedObject var vm: HJGameViewModel
    var store: HJStore
    var available: CGSize

    private var gridW: Int { vm.state.gridW }
    private var gridH: Int { vm.state.gridH }

    private var cellSize: CGFloat {
        let padding: CGFloat = 12
        let w = max(50, available.width - padding * 2)
        let h = max(50, available.height - padding * 2)
        return min(w / CGFloat(gridW), h / CGFloat(gridH))
    }
    private var boardSize: CGSize {
        CGSize(width: cellSize * CGFloat(gridW), height: cellSize * CGFloat(gridH))
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
                .stroke(Color.white.opacity(vm.state.night ? 0.06 : 0.25), lineWidth: 1)
            }
            ForEach(0..<gridH, id: \.self) { y in
                Path { p in
                    p.move(to: CGPoint(x: 0, y: CGFloat(y) * cellSize))
                    p.addLine(to: CGPoint(x: boardSize.width, y: CGFloat(y) * cellSize))
                }
                .stroke(Color.white.opacity(vm.state.night ? 0.06 : 0.25), lineWidth: 1)
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
                            .stroke(HJTheme.navy.opacity(0.22), lineWidth: 1.6)
                            .frame(width: cellSize * 0.6, height: cellSize * 0.6)
                            .position(cellCenter(x: x, y: lane.index))
                    }
                } else {
                    ForEach(0..<gridH, id: \.self) { y in
                        HJArrowShape(direction: lane.push)
                            .stroke(HJTheme.navy.opacity(0.22), lineWidth: 1.6)
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
                            .stroke(HJTheme.driftwood.opacity(0.8), lineWidth: 1.4)
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
                           night: vm.state.night)
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

    private var hull: Color { HJTheme.hullColors[boat.hullIndex % HJTheme.hullColors.count] }
    private var w: CGFloat { CGFloat(boat.width) * cellSize * 0.92 }
    private var h: CGFloat { CGFloat(boat.height) * cellSize * 0.92 }

    var body: some View {
        ZStack {
            HJHullShape(bow: boat.bow, isBarge: boat.isBarge)
                .fill(hull)
            HJHullShape(bow: boat.bow, isBarge: boat.isBarge)
                .stroke(Color.black.opacity(0.25), lineWidth: 1.5)
            if patterns {
                HJPatternOverlay(index: boat.hullIndex)
                    .clipShape(HJHullShape(bow: boat.bow, isBarge: boat.isBarge))
            }
            // deck stripe pointing at the bow
            HJArrowShape(direction: boat.bow)
                .stroke(Color.white.opacity(0.85), lineWidth: 2)
                .frame(width: min(w, h) * 0.5, height: min(w, h) * 0.5)
            if anchored {
                Circle()
                    .fill(HJTheme.buoyRed)
                    .frame(width: cellSize * 0.3, height: cellSize * 0.3)
                    .overlay(
                        HJLockShape()
                            .stroke(Color.white, lineWidth: 1.4)
                            .frame(width: cellSize * 0.18, height: cellSize * 0.18)
                    )
                    .offset(x: w * 0.28, y: -h * 0.28)
            }
        }
        .frame(width: w, height: h)
        .offset(x: shaking ? 4 : 0)
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
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            switch index % 4 {
            case 0:
                Path { p in
                    var x: CGFloat = -h
                    while x < w + h {
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x + h, y: h))
                        x += 10
                    }
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 2)
            case 1:
                Path { p in
                    var y: CGFloat = 4
                    while y < h {
                        var x: CGFloat = 4
                        while x < w {
                            p.addEllipse(in: CGRect(x: x, y: y, width: 3, height: 3))
                            x += 9
                        }
                        y += 9
                    }
                }
                .fill(Color.white.opacity(0.4))
            case 2:
                Path { p in
                    var y: CGFloat = 3
                    while y < h {
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                        y += 8
                    }
                }
                .stroke(Color.white.opacity(0.3), lineWidth: 1.6)
            default:
                EmptyView()
            }
        }
    }
}
