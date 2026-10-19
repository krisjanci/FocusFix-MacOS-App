import SwiftUI

// A short introduction, not a loading task. It never starts or pauses recording.
struct LaunchScreen: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false
    @State private var ready = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            FocusFixLaunchLogo(ready: ready)
                .frame(width: 180, height: 180)
                .scaleEffect(pressed ? 0.88 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FocusFix")
        .task { await animate() }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { onFinish() }
        }
    }

    @MainActor private func animate() async {
        // Don't make people who prefer reduced motion sit through a fake load.
        guard !reduceMotion else { onFinish(); return }
        do {
            try await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeInOut(duration: 0.13)) { pressed = true }
            try await Task.sleep(for: .milliseconds(130))
            withAnimation(.spring(duration: 0.36, bounce: 0.4)) { pressed = false }
            try await Task.sleep(for: .milliseconds(280))
            withAnimation(.easeInOut(duration: 0.5)) { ready = true }
            try await Task.sleep(for: .milliseconds(650))
            finish()
        } catch {
            // Closing the window cancels its task. Never leave a stuck splash behind.
            onFinish()
        }
    }

    private func finish() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { onFinish() }
    }
}

// Draw the existing logo as separate layers so only the ring turns, not the symbol.
// The app icon asset itself stays unchanged.
struct FocusFixLaunchLogo: View {
    let ready: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .fill(Color(red: 0.98, green: 0.98, blue: 0.97))
                    .shadow(color: .black.opacity(0.08), radius: size * 0.08, y: size * 0.03)

                LaunchRing()
                    .stroke(LinearGradient(colors: [
                        Color(red: 0.02, green: 0.61, blue: 0.55),
                        Color(red: 0.38, green: 0.81, blue: 0.66)
                    ], startPoint: .leading, endPoint: .trailing), lineWidth: size * 0.12)
                    // Starting a quarter-turn back makes the final logo upright.
                    .rotationEffect(.degrees(ready ? 0 : -90))

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
            .saturation(ready ? 1 : 0.25)
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct LaunchRing: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 0.32
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for quarter in 0..<4 {
            let start = Angle.degrees(Double(quarter * 90) + 4)
            // Explicit moves keep the four arcs separate rather than joining gaps.
            path.move(to: CGPoint(x: center.x + radius * cos(start.radians),
                                  y: center.y + radius * sin(start.radians)))
            path.addArc(center: center, radius: radius,
                startAngle: start,
                endAngle: .degrees(Double(quarter * 90) + 86), clockwise: false)
        }
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
