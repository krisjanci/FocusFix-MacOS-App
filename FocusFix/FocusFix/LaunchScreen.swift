import SwiftUI

// A short introduction, not a loading task. It never starts or pauses recording.
struct LaunchScreen: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false
    @State private var ready = false
    @State private var symbolScale = 1.0
    @State private var symbolOpacity = 1.0
    @State private var spread = 0.0
    @State private var finished = false

    var body: some View {
        ZStack {
            // The real app is already underneath. Reveal it as the ring opens out.
            Color(nsColor: .windowBackgroundColor).opacity(1 - spread)
            FocusFixLaunchLogo(ready: ready, spread: spread,
                symbolScale: symbolScale, symbolOpacity: symbolOpacity)
                .frame(width: 180, height: 180)
                .scaleEffect(pressed ? 0.78 : 1)
        }
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FocusFix")
        .task { await animate() }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { finish() }
        }
    }

    @MainActor private func animate() async {
        // Don't make people who prefer reduced motion sit through a fake load.
        guard !reduceMotion else { finish(); return }
        do {
            // Hold the play logo long enough to read before the first press.
            try await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeInOut(duration: 0.18)) { pressed = true }
            try await Task.sleep(for: .milliseconds(180))
            withAnimation(.spring(duration: 0.42, bounce: 0.48)) { pressed = false }
            try await Task.sleep(for: .milliseconds(420))
            withAnimation(.easeInOut(duration: 0.7)) { ready = true }
            try await Task.sleep(for: .milliseconds(940)) // Turn, then hold the pause logo.

            // A second press belongs to the pause symbol only, not the whole tile.
            withAnimation(.easeInOut(duration: 0.16)) { symbolScale = 0.72 }
            try await Task.sleep(for: .milliseconds(160))
            withAnimation(.spring(duration: 0.25, bounce: 0.4)) { symbolScale = 1.12 }
            try await Task.sleep(for: .milliseconds(160))
            withAnimation(.easeIn(duration: 0.28)) {
                symbolScale = 0.001
                symbolOpacity = 0
            }
            try await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeInOut(duration: 0.85)) { spread = 1 }
            try await Task.sleep(for: .milliseconds(880))
            finish()
        } catch {
            // Closing the window cancels its task. Never leave a stuck splash behind.
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}

// Draw the existing logo as separate layers so only the ring turns, not the symbol.
// The app icon asset itself stays unchanged.
struct FocusFixLaunchLogo: View {
    let ready: Bool
    var spread = 0.0
    var symbolScale = 1.0
    var symbolOpacity = 1.0

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .fill(Color(red: 0.98, green: 0.98, blue: 0.97))
                    .shadow(color: .black.opacity(0.08), radius: size * 0.08, y: size * 0.03)
                    .scaleEffect(1 + spread * 0.4)
                    .opacity(1 - spread)

                ZStack {
                    ForEach(0..<4) { quarter in
                        let angle = Double(quarter * 90 + 45) * .pi / 180
                        LaunchRingSegment(quarter: quarter)
                            .stroke(LinearGradient(colors: [
                                Color(red: 0.02, green: 0.61, blue: 0.55),
                                Color(red: 0.38, green: 0.81, blue: 0.66)
                            ], startPoint: .leading, endPoint: .trailing), lineWidth: size * 0.12)
                            // Each piece gets bigger around its own center as it flies out.
                            .scaleEffect(1 + spread * 1.8, anchor: UnitPoint(
                                x: 0.5 + 0.23 * cos(angle), y: 0.5 + 0.23 * sin(angle)))
                            .offset(x: size * 1.8 * spread * cos(angle),
                                    y: size * 1.8 * spread * sin(angle))
                            .opacity(1 - spread)
                    }
                }
                // Starting a quarter-turn back makes the final logo upright.
                .rotationEffect(.degrees(ready ? 0 : -90))

                ZStack {
                    LaunchPlaySymbol()
                        .fill(Color(red: 0.10, green: 0.22, blue: 0.32))
                        .frame(width: size * 0.24, height: size * 0.28)
                        .offset(x: size * 0.015)
                        .opacity(ready ? 0 : 1)

                    HStack(spacing: size * 0.055) {
                        ForEach(0..<2) { _ in
                            RoundedRectangle(cornerRadius: size * 0.035)
                                .fill(Color(red: 0.10, green: 0.22, blue: 0.32))
                                .frame(width: size * 0.10, height: size * 0.265)
                        }
                    }.opacity(ready ? 1 : 0)
                }
                .scaleEffect(symbolScale)
                .opacity(symbolOpacity)
            }
            .saturation(ready ? 1 : 0.25)
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct LaunchRingSegment: Shape {
    let quarter: Int

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 0.32
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        let start = Angle.degrees(Double(quarter * 90) + 4)
        path.move(to: CGPoint(x: center.x + radius * cos(start.radians),
                              y: center.y + radius * sin(start.radians)))
        path.addArc(center: center, radius: radius, startAngle: start,
            endAngle: .degrees(Double(quarter * 90) + 86), clockwise: false)
        return path
    }
}

private struct LaunchPlaySymbol: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
