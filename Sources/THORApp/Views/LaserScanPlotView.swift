import SwiftUI
import THORShared

struct LaserScanPlotView: View {
    let scan: LaserScanFrame

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = size * 0.42

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                Circle()
                    .scale(0.66)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                Circle()
                    .scale(0.33)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)

                Path { path in
                    for (index, range) in scan.ranges.enumerated() {
                        let angle = scan.angleMin + (Double(index) * scan.angleIncrement)
                        let normalized = max(0, min(range / max(scan.rangeMax, 0.0001), 1))
                        let pointRadius = radius * normalized
                        let point = CGPoint(
                            x: center.x + CGFloat(cos(angle - (.pi / 2)) * pointRadius),
                            y: center.y + CGFloat(sin(angle - (.pi / 2)) * pointRadius)
                        )
                        if index == 0 {
                            path.move(to: center)
                            path.addLine(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color.blue.opacity(0.25), Color.green.opacity(0.45)], startPoint: .top, endPoint: .bottom))

                Path { path in
                    for (index, range) in scan.ranges.enumerated() {
                        let angle = scan.angleMin + (Double(index) * scan.angleIncrement)
                        let normalized = max(0, min(range / max(scan.rangeMax, 0.0001), 1))
                        let pointRadius = radius * normalized
                        let point = CGPoint(
                            x: center.x + CGFloat(cos(angle - (.pi / 2)) * pointRadius),
                            y: center.y + CGFloat(sin(angle - (.pi / 2)) * pointRadius)
                        )
                        if index == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(Color.accentColor, lineWidth: 2)
            }
            .padding(24)
        }
        .frame(minHeight: 280)
        .background(Color(.secondarySystemFill).opacity(0.45))
        .clipShape(.rect(cornerRadius: 16))
    }
}
