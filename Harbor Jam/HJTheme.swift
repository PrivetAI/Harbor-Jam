import SwiftUI

/// The nautical-chart palette. Every colour in the app comes from here, and the
/// same hex values are hard-coded in the SVG sprites — move one and the other has
/// to move with it.
enum HJTheme {
    static let chartDeep = Color(red: 0.047, green: 0.125, blue: 0.200)  // #0C2033
    static let chartGrid = Color(red: 0.086, green: 0.204, blue: 0.294)  // #16344B
    static let contour   = Color(red: 0.184, green: 0.424, blue: 0.525)  // #2F6C86
    static let cyan      = Color(red: 0.373, green: 0.816, blue: 0.910)  // #5FD0E8
    static let cyanSoft  = Color(red: 0.624, green: 0.910, blue: 0.961)  // #9FE8F5
    static let hullFill  = Color(red: 0.071, green: 0.227, blue: 0.322)  // #123A52
    static let gold      = Color(red: 0.949, green: 0.784, blue: 0.251)  // #F2C840
    static let alert     = Color(red: 0.776, green: 0.271, blue: 0.239)  // #C6453D
    static let success   = Color(red: 0.243, green: 0.549, blue: 0.455)  // #3E8C74
    static let warn      = Color(red: 0.910, green: 0.573, blue: 0.353)  // #E8925A

    static let cardBG  = Color(red: 0.071, green: 0.161, blue: 0.243)
    static let inkSoft = Color(red: 0.624, green: 0.910, blue: 0.961).opacity(0.55)

    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom("Georgia", size: size).weight(weight)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom("Menlo", size: size).weight(weight)
    }
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

}

/// Heading for the arrow glyph. Local to the theme — the board is no longer a
/// grid with compass headings, and the old `HJDirection` left with the engine.
enum HJArrowDirection { case north, east, south, west }

// MARK: - Custom shape icons (no SF Symbols anywhere)

struct HJStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.42
        for i in 0..<10 {
            let ang = (Double(i) * .pi / 5) - .pi / 2
            let r = i % 2 == 0 ? outer : inner
            let pt = CGPoint(x: c.x + CGFloat(cos(ang)) * r, y: c.y + CGFloat(sin(ang)) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

struct HJWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let h = rect.height, w = rect.width
        for row in 0..<2 {
            let y = rect.minY + h * (0.35 + CGFloat(row) * 0.35)
            p.move(to: CGPoint(x: rect.minX, y: y))
            p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.5, y: y),
                           control: CGPoint(x: rect.minX + w * 0.25, y: y - h * 0.28))
            p.addQuadCurve(to: CGPoint(x: rect.minX + w, y: y),
                           control: CGPoint(x: rect.minX + w * 0.75, y: y + h * 0.28))
        }
        return p
    }
}

struct HJChevronShape: Shape {
    var pointsRight = true
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if pointsRight {
            p.move(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.maxX - rect.width * 0.3, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.3, y: rect.maxY))
        }
        return p
    }
}

struct HJGearShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let teeth = 8
        for i in 0..<(teeth * 2) {
            let ang = Double(i) * .pi / Double(teeth)
            let radius = i % 2 == 0 ? r : r * 0.72
            let pt = CGPoint(x: c.x + CGFloat(cos(ang)) * radius, y: c.y + CGFloat(sin(ang)) * radius)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: c.x - r * 0.3, y: c.y - r * 0.3, width: r * 0.6, height: r * 0.6))
        return p
    }
}

struct HJTrophyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // cup
        p.move(to: CGPoint(x: rect.minX + w * 0.22, y: rect.minY + h * 0.08))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.78, y: rect.minY + h * 0.08))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY + h * 0.62),
                       control: CGPoint(x: rect.minX + w * 0.82, y: rect.minY + h * 0.55))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.22, y: rect.minY + h * 0.08),
                       control: CGPoint(x: rect.minX + w * 0.18, y: rect.minY + h * 0.55))
        p.closeSubpath()
        // stem + base
        p.addRect(CGRect(x: rect.minX + w * 0.44, y: rect.minY + h * 0.62, width: w * 0.12, height: h * 0.18))
        p.addRect(CGRect(x: rect.minX + w * 0.28, y: rect.minY + h * 0.82, width: w * 0.44, height: h * 0.1))
        return p
    }
}

struct HJLockShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.addRoundedRect(in: CGRect(x: rect.minX + w * 0.15, y: rect.minY + h * 0.45, width: w * 0.7, height: h * 0.5),
                         cornerSize: CGSize(width: w * 0.1, height: w * 0.1))
        p.move(to: CGPoint(x: rect.minX + w * 0.3, y: rect.minY + h * 0.45))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.3, y: rect.minY + h * 0.28))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.7, y: rect.minY + h * 0.28),
                       control: CGPoint(x: rect.midX, y: rect.minY - h * 0.05))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.7, y: rect.minY + h * 0.45))
        return p
    }
}

struct HJUndoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) * 0.36
        p.addArc(center: c, radius: r, startAngle: .degrees(-40), endAngle: .degrees(200), clockwise: false)
        // arrow head at start of arc
        let ang = -40.0 * .pi / 180
        let tip = CGPoint(x: c.x + CGFloat(cos(ang)) * r, y: c.y + CGFloat(sin(ang)) * r)
        p.move(to: CGPoint(x: tip.x - rect.width * 0.16, y: tip.y - rect.height * 0.02))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x + rect.width * 0.02, y: tip.y - rect.height * 0.18))
        return p
    }
}

struct HJRestartShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) * 0.36
        p.addArc(center: c, radius: r, startAngle: .degrees(30), endAngle: .degrees(330), clockwise: false)
        let ang = 30.0 * .pi / 180
        let tip = CGPoint(x: c.x + CGFloat(cos(ang)) * r, y: c.y + CGFloat(sin(ang)) * r)
        p.move(to: CGPoint(x: tip.x + rect.width * 0.14, y: tip.y - rect.height * 0.06))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x + rect.width * 0.1, y: tip.y + rect.height * 0.16))
        return p
    }
}

struct HJCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.maxY - rect.height * 0.2))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.18))
        return p
    }
}

struct HJPauseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.2, y: rect.minY, width: rect.width * 0.2, height: rect.height), cornerSize: CGSize(width: 2, height: 2))
        p.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.6, y: rect.minY, width: rect.width * 0.2, height: rect.height), cornerSize: CGSize(width: 2, height: 2))
        return p
    }
}

struct HJArrowShape: Shape {
    var direction: HJArrowDirection
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // arrow pointing East in local space, rotate for others
        p.move(to: CGPoint(x: 0.15 * w, y: 0.5 * h))
        p.addLine(to: CGPoint(x: 0.72 * w, y: 0.5 * h))
        p.move(to: CGPoint(x: 0.5 * w, y: 0.28 * h))
        p.addLine(to: CGPoint(x: 0.78 * w, y: 0.5 * h))
        p.addLine(to: CGPoint(x: 0.5 * w, y: 0.72 * h))
        let angle: CGFloat
        switch direction {
        case .east: angle = 0
        case .south: angle = .pi / 2
        case .west: angle = .pi
        case .north: angle = -.pi / 2
        }
        let t = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .rotated(by: angle)
            .translatedBy(x: -rect.midX, y: -rect.midY)
        return p.applying(t)
    }
}

struct HJTugShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) * 0.34
        p.addArc(center: c, radius: r, startAngle: .degrees(-60), endAngle: .degrees(180), clockwise: false)
        let ang = -60.0 * .pi / 180
        let tip = CGPoint(x: c.x + CGFloat(cos(ang)) * r, y: c.y + CGFloat(sin(ang)) * r)
        p.move(to: CGPoint(x: tip.x - rect.width * 0.18, y: tip.y - rect.height * 0.05))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x - rect.width * 0.02, y: tip.y - rect.height * 0.2))
        return p
    }
}

struct HJSpeakerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.minX + 0.1 * w, y: rect.minY + 0.38 * h))
        p.addLine(to: CGPoint(x: rect.minX + 0.32 * w, y: rect.minY + 0.38 * h))
        p.addLine(to: CGPoint(x: rect.minX + 0.55 * w, y: rect.minY + 0.15 * h))
        p.addLine(to: CGPoint(x: rect.minX + 0.55 * w, y: rect.minY + 0.85 * h))
        p.addLine(to: CGPoint(x: rect.minX + 0.32 * w, y: rect.minY + 0.62 * h))
        p.addLine(to: CGPoint(x: rect.minX + 0.1 * w, y: rect.minY + 0.62 * h))
        p.closeSubpath()
        p.move(to: CGPoint(x: rect.minX + 0.68 * w, y: rect.minY + 0.35 * h))
        p.addQuadCurve(to: CGPoint(x: rect.minX + 0.68 * w, y: rect.minY + 0.65 * h),
                       control: CGPoint(x: rect.minX + 0.85 * w, y: rect.midY))
        return p
    }
}

struct HJPulseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY + rect.height * 0.15))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.6, y: rect.maxY - rect.height * 0.15))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

struct HJBookShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.midX, y: rect.minY + 0.15 * h))
        p.addQuadCurve(to: CGPoint(x: rect.minX + 0.08 * w, y: rect.minY + 0.12 * h),
                       control: CGPoint(x: rect.minX + 0.28 * w, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + 0.08 * w, y: rect.maxY - 0.1 * h))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY - 0.05 * h),
                       control: CGPoint(x: rect.minX + 0.28 * w, y: rect.maxY - 0.2 * h))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - 0.08 * w, y: rect.maxY - 0.1 * h),
                       control: CGPoint(x: rect.maxX - 0.28 * w, y: rect.maxY - 0.2 * h))
        p.addLine(to: CGPoint(x: rect.maxX - 0.08 * w, y: rect.minY + 0.12 * h))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY + 0.15 * h),
                       control: CGPoint(x: rect.maxX - 0.28 * w, y: rect.minY))
        p.move(to: CGPoint(x: rect.midX, y: rect.minY + 0.15 * h))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 0.05 * h))
        return p
    }
}

struct HJCloseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let inset = min(rect.width, rect.height) * 0.2
        p.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
        p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        p.move(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        p.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        return p
    }
}

struct HJStarIcon: View {
    var size: CGFloat
    var filled: Bool
    var color: Color = HJTheme.gold
    var body: some View {
        ZStack {
            if filled {
                HJStarShape().fill(color)
            } else {
                HJStarShape().stroke(color.opacity(0.45), lineWidth: max(1.2, size * 0.06))
            }
        }
        .frame(width: size, height: size)
    }
}

struct HJStarsRow: View {
    var stars: Int
    var size: CGFloat = 14
    var body: some View {
        HStack(spacing: size * 0.2) {
            ForEach(0..<3, id: \.self) { i in
                HJStarIcon(size: size, filled: i < stars)
            }
        }
    }
}
