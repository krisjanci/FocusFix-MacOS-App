import SwiftUI

struct BadgeArtwork: View {
    let badge: FocusBadge
    var earned = true
    private var rank: Int { badge.rank }
    private var colors: [Color] {
        switch rank {
        case 0: return [Color(red: 0.25, green: 0.88, blue: 0.77), Color(red: 0.01, green: 0.37, blue: 0.36)]
        case 1: return [.init(red: 0.89, green: 0.66, blue: 0.39), .init(red: 0.35, green: 0.20, blue: 0.12)]
        case 2: return [.init(red: 0.88, green: 0.96, blue: 1), .init(red: 0.27, green: 0.53, blue: 0.60)]
        case 3: return [.mint, .init(red: 0.01, green: 0.35, blue: 0.25)]
        case 4: return [.init(red: 1, green: 0.85, blue: 0.38), .init(red: 0.65, green: 0.39, blue: 0.08)]
        case 5: return [.init(red: 0.40, green: 0.74, blue: 1), .init(red: 0.11, green: 0.21, blue: 0.62)]
        case 6: return [.init(red: 0.85, green: 0.72, blue: 1), .init(red: 0.36, green: 0.16, blue: 0.63)]
        default: return [.mint, .init(red: 0.65, green: 0.44, blue: 0.95), .init(red: 1, green: 0.79, blue: 0.30)]
        }
    }
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(colors[0].opacity(0.12)).blur(radius: size * 0.10).padding(size * 0.08)
                if rank == 1 {
                    ForEach(0..<5, id: \.self) { index in
                        Diamond().fill(colors[0])
                            .frame(width: size * 0.035, height: size * 0.09)
                            .offset(y: -size * 0.39)
                            .rotationEffect(.degrees(Double(index) * 30 - 60))
                    }
                }
                if rank >= 4 {
                    ForEach(0..<(rank >= 6 ? 16 : 12), id: \.self) { index in
                        Diamond().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                            .frame(width: size * 0.08, height: size * (rank == 7 ? 0.21 : 0.14))
                            .offset(y: -size * 0.35)
                            .rotationEffect(.degrees(Double(index) * (rank >= 6 ? 22.5 : 30)))
                    }
                }
                if rank >= 3 {
                    ForEach(0..<12, id: \.self) { index in
                        let left = index < 6
                        let step = index % 6
                        Capsule().fill(rank >= 5 ? Color(red: 0.87, green: 0.72, blue: 0.37) : colors[0])
                            .frame(width: size * 0.055, height: size * 0.115)
                            .rotationEffect(.degrees(left ? -38 : 38))
                            .offset(x: (left ? -1 : 1) * size * (0.30 + sin(Double(step) * 0.5) * 0.10),
                                    y: size * (0.24 - Double(step) * 0.085))
                    }
                }
                BadgeSilhouette(sides: rank == 0 ? 64 : rank >= 5 ? 10 : 6)
                    .fill(LinearGradient(colors: colors + [colors[0]], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(BadgeSilhouette(sides: rank == 0 ? 64 : rank >= 5 ? 10 : 6).stroke(.white.opacity(0.65), lineWidth: size * 0.009))
                    .frame(width: size * 0.67, height: size * 0.75)
                    .shadow(color: colors.last!.opacity(0.28), radius: size * 0.025, y: size * 0.025)
                BadgeSilhouette(sides: rank == 0 ? 64 : rank >= 5 ? 10 : 6)
                    .fill(LinearGradient(colors: [Color(red: 0.03, green: 0.30, blue: 0.29), Color(red: 0.01, green: 0.14, blue: 0.18)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.56, height: size * 0.63)
                Circle().trim(from: 0.06, to: 0.94)
                    .stroke(colors[0].opacity(0.7), style: StrokeStyle(lineWidth: size * 0.009, lineCap: .round))
                    .rotationEffect(.degrees(90)).frame(width: size * 0.43, height: size * 0.43)
                Circle().stroke(.white.opacity(0.14), lineWidth: 1).frame(width: size * 0.38, height: size * 0.38)
                VStack(spacing: size * 0.025) {
                    Image(systemName: rank == 7 ? "crown.fill" : rank == 0 ? "sparkle" : "scope")
                        .font(.system(size: size * (rank == 0 ? 0.25 : 0.10), weight: .light))
                    if badge.days > 0 {
                        Text("\(badge.days)").font(.system(size: size * 0.22, weight: .semibold, design: .rounded))
                            .minimumScaleFactor(0.7)
                        Text("FOCUS DAYS").font(.system(size: size * 0.038, weight: .bold)).tracking(size * 0.012)
                    }
                }.foregroundStyle(LinearGradient(colors: [.white, colors[0]], startPoint: .top, endPoint: .bottom))
                if rank >= 2 {
                    ForEach(0..<min(rank, 5), id: \.self) { index in
                        Image(systemName: "sparkle").font(.system(size: size * 0.045))
                            .foregroundStyle(rank >= 4 ? .yellow.opacity(0.9) : .white.opacity(0.8))
                            .offset(x: CGFloat(index - min(rank, 5) / 2) * size * 0.075, y: size * 0.28)
                    }
                }
            }
            .saturation(earned ? 1 : 0).opacity(earned ? 1 : 0.38)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct BadgeSilhouette: Shape {
    let sides: Int
    func path(in rect: CGRect) -> Path {
        Path { path in
            for index in 0..<sides {
                let angle = Double(index) * .pi * 2 / Double(sides) - .pi / 2
                let point = CGPoint(x: rect.midX + cos(angle) * rect.width / 2, y: rect.midY + sin(angle) * rect.height / 2)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }
}
private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.midY)); path.closeSubpath()
        }
    }
}

struct BadgeUnreadDot: View {
    var body: some View {
        Circle().fill(.red).frame(width: 7, height: 7).accessibilityLabel("New badges")
    }
}
