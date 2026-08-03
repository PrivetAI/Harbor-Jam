import SwiftUI

struct HarborJamLoadingScreen: View {
    @State private var phase = false

    var body: some View {
        ZStack {
            HJTheme.chartDeep.ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .stroke(HJTheme.contour, lineWidth: 1.5)
                        .frame(width: 92, height: 92)
                    Circle()
                        .fill(HJTheme.hullFill)
                        .frame(width: 76, height: 76)
                    HJWaveShape()
                        .stroke(HJTheme.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 52, height: 30)
                        .offset(y: phase ? -3 : 3)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: phase)
                }
                Text("Harbor Jam")
                    .font(HJTheme.display(28))
                    .foregroundColor(HJTheme.cyanSoft)
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(HJTheme.gold)
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
