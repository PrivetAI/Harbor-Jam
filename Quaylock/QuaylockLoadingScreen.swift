import SwiftUI

/// Splash shown only while the launch link check is in flight (5 s ceiling).
///
/// Deliberately has **no animation at all** — no `repeatForever`, no `onAppear`
/// `withAnimation`. A splash was tried here once before and removed again
/// because its `repeatForever` animations kept the removed view alive long
/// enough to swallow taps on the tab bar underneath. A still image cannot
/// reproduce that, so the screen is drawn once and torn down cleanly the moment
/// the check resolves.
struct QuaylockLoadingScreen: View {
    var body: some View {
        ZStack {
            QLTheme.chartDeep.ignoresSafeArea()

            VStack(spacing: 26) {
                // A berth: quay wall, a moored hull, and the water line.
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(QLTheme.contour.opacity(0.55))
                        .frame(width: 132, height: 6)
                        .offset(y: 34)

                    HullMark()
                        .fill(QLTheme.hullFill)
                        .overlay(HullMark().stroke(QLTheme.cyan, lineWidth: 1.6))
                        .frame(width: 86, height: 34)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(QLTheme.cyan)
                        .frame(width: 3, height: 30)
                        .offset(x: -34, y: -26)

                    Circle()
                        .fill(QLTheme.gold)
                        .frame(width: 8, height: 8)
                        .offset(x: -34, y: -42)
                }
                .frame(height: 110)

                Text("Quaylock")
                    .font(QLTheme.display(28))
                    .foregroundColor(QLTheme.cyanSoft)

                Text("Sounding the channel...")
                    .font(QLTheme.body(14, weight: .medium))
                    .foregroundColor(QLTheme.inkSoft)
            }
        }
    }
}

/// Flat-bottomed hull with a raked bow — the same silhouette the board uses.
private struct HullMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - rect.height * 0.55, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.height * 0.55, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
