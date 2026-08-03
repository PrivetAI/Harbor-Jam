import SwiftUI

struct QuaylockLoadingScreen: View {
    @State private var phase = false

    var body: some View {
        ZStack {
            QLTheme.chartDeep.ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .stroke(QLTheme.contour, lineWidth: 1.5)
                        .frame(width: 92, height: 92)
                    Circle()
                        .fill(QLTheme.hullFill)
                        .frame(width: 76, height: 76)
                    QLWaveShape()
                        .stroke(QLTheme.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 52, height: 30)
                        .offset(y: phase ? -3 : 3)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: phase)
                }
                Text("Quaylock")
                    .font(QLTheme.display(28))
                    .foregroundColor(QLTheme.cyanSoft)
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(QLTheme.gold)
                            .frame(width: 9, height: 9)
                            .opacity(phase ? 0.3 : 1)
                            .animation(.easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.2), value: phase)
                    }
                }
            }
        }
        .onAppear { phase = true }
    }
}
