// MARK: - FF: PROGRESS UI
import SwiftUI

struct DailyProgressCard: View {
    @ObservedObject var tracker: ActivityTracker
    @ObservedObject private var social = SocialController.shared
    var body: some View {
        // Refresh the local day even when the app is idle across midnight.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let calendar = DailyProgress.calendar()
            let progress = tracker.dailyProgress
            let day = progress.day(at: context.date, calendar: calendar)
            let streak = progress.streak(at: context.date, calendar: calendar)
            let weekend = DailyProgress.isWeekend(context.date, calendar: calendar)
            let complete = day.workSeconds >= DailyProgress.goalSeconds
            DailyProgressDisplay(workMinutes: Int(day.workSeconds / 60), streak: streak,
                breakCount: day.completedBreakIDs.count, weekend: weekend, complete: complete,
                recharged: tracker.rechargeDate.map {
                    calendar.isDate($0, inSameDayAs: context.date) && context.date.timeIntervalSince($0) < 20
                } ?? false, notice: tracker.progressNotice ?? (social.declaredWorkSyncHeld ? "Work progress is waiting to sync." : nil), workSeconds: day.workSeconds,
                freezes: progress.tokensRemaining(at: context.date, calendar: calendar), pending: social.pendingConfirmation,
                active: tracker.isRecording && tracker.userContext == .work && tracker.breakPhase == .work)
                .onChange(of: DailyProgress.key(for: context.date, calendar: calendar)) { _, _ in
                    tracker.reconcileProgress()
                    Task { await social.refresh() }
                }
        }
    }
}

struct DailyProgressDisplay: View {
    let workMinutes: Int
    let streak: Int
    let breakCount: Int
    var weekend = false
    var complete = false
    var recharged = false
    var notice: String? = nil
    var workSeconds: Double = 0
    var freezes = 3
    var pending = false
    var active = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)
    private var fillFraction: Double { min(max(workSeconds / DailyProgress.goalSeconds, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Declared work · \(workMinutes) / 60 min",
                      systemImage: complete ? "checkmark.circle.fill" : "target")
                    .font(.callout.weight(.medium))
                Spacer()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill((active ? teal : .gray).opacity(0.12))
                    Capsule().fill(active ? teal : Color(red: 0.42, green: 0.55, blue: 0.53))
                        .overlay {
                            if active && !complete && !reduceMotion && fillFraction > 0 {
                                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                                    let phase = context.date.timeIntervalSinceReferenceDate
                                        .truncatingRemainder(dividingBy: 1.8) / 1.8
                                    let highlightWidth = max(geometry.size.width / 3, 24)
                                    LinearGradient(colors: [.clear, .white.opacity(0.5), .clear],
                                                   startPoint: .leading, endPoint: .trailing)
                                        .frame(width: highlightWidth)
                                        .offset(x: -highlightWidth + (geometry.size.width + highlightWidth) * phase)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(width: geometry.size.width * fillFraction)
                        .clipShape(Capsule())
                        .animation(active && !reduceMotion ? .linear(duration: 1) : nil, value: fillFraction)
                }
            }.frame(height: 7)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: active)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Daily work goal")
                .accessibilityValue("\(workMinutes) of 60 minutes")
            HStack {
                Label(streak > 0 ? "\(streak)-day weekday streak" : "Start a new streak",
                      systemImage: "flame")
                Spacer()
                Label(breakCount > 0 ? "Healthy habit complete" : "Take a 1-min break", systemImage: "leaf")
            }
            .font(.caption).foregroundStyle(.secondary)
            HStack {
                Label("\(freezes) / 3 freezes this month", systemImage: "snowflake")
                Spacer()
                if pending { Text("Pending sync") }
            }.font(.caption).foregroundStyle(.secondary)
            if complete {
                Text("Daily goal complete. Nice work!").font(.caption).foregroundStyle(teal)
            }
            if recharged {
                Text("You made time to recharge.").font(.caption).foregroundStyle(teal)
            }
            if weekend {
                Text("Weekends are optional. Your weekday streak takes a break too.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ProgressMenuSummary: View {
    @ObservedObject var tracker: ActivityTracker
    @ObservedObject private var social = SocialController.shared

    var body: some View {
        // Native menus cannot host TimelineView: its scheduled graph updates can
        // reenter AppKit menu construction and overflow the stack when opened.
        // The observed tracker supplies fresh snapshots when progress changes.
        let date = Date()
        let calendar = DailyProgress.calendar()
        let progress = tracker.dailyProgress
        let day = progress.day(at: date, calendar: calendar)
        let status = progress.streakStatus(at: date, calendar: calendar)
        Text("Declared work: \(Int(day.workSeconds / 60))/60 min · \(status.count)-day weekday streak")
        Text("Breaks taken today: \(day.completedBreakIDs.count)")
    }
}

struct WorkStreakBadge: View {
    @ObservedObject var tracker: ActivityTracker
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let status = tracker.dailyProgress.streakStatus(at: context.date, calendar: DailyProgress.calendar())
            WorkStreakFlame(status: status)
        }
    }
}

// Shared value-only appearance for the main header and group member streaks.
struct WorkStreakFlame: View {
    let status: WorkStreakStatus
    var compact = false
    private var tint: Color { status.count == 0 ? .secondary : status.frozen ? .blue : .orange }
    var body: some View {
        HStack(spacing: compact ? 5 : 7) {
            if status.count > 0 {
                BurningStreakFlame(size: compact ? 18 : 23, frozen: status.frozen)
            } else {
                StreakFireContour(time: 0)
                    .fill(.secondary)
                    .frame(width: compact ? 18 : 23, height: (compact ? 18 : 23) * 1.18)
            }
            Text("\(status.count)").font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 0 : 12).padding(.vertical, compact ? 0 : 8)
        .background(tint.opacity(compact ? 0 : 0.08), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.description)
        .help(status.description)
    }
}

// The base stays planted: only the upper contour and heat glow flicker.
private struct BurningStreakFlame: View {
    let size: CGFloat
    var frozen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.controlActiveState) private var activeState
    @State private var visible = false
    private var animated: Bool { visible && !frozen && !reduceMotion && scenePhase == .active && activeState == .key }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animated)) { context in
            let time = animated ? context.date.timeIntervalSinceReferenceDate : 0
            let heat = (sin(time * 9) + sin(time * 15 + 1)) / 2
            ZStack {
                StreakFireContour(time: time)
                    .fill(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .bottom, endPoint: .top))
                    .shadow(color: .orange.opacity(frozen ? 0.12 : 0.26 + heat * 0.08), radius: 2)
                    .padding(.horizontal, frozen ? size * 0.16 : 0)
                    .padding(.vertical, frozen ? size * 0.10 : 0)
                if frozen {
                    // Warm fire remains visible through a faceted, translucent ice block.
                    RoundedRectangle(cornerRadius: size * 0.16)
                        .fill(LinearGradient(colors: [.cyan.opacity(0.20), .blue.opacity(0.12), .cyan.opacity(0.32)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: size * 0.16)
                        .strokeBorder(.cyan.opacity(0.85), lineWidth: 1)
                    Path { path in
                        path.move(to: CGPoint(x: size * 0.12, y: size * 0.40))
                        path.addLine(to: CGPoint(x: size * 0.29, y: size * 0.14))
                        path.addLine(to: CGPoint(x: size * 0.70, y: size * 0.10))
                        path.move(to: CGPoint(x: size * 0.72, y: size * 0.91))
                        path.addLine(to: CGPoint(x: size * 0.88, y: size * 0.71))
                    }
                    .stroke(.white.opacity(0.80), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: size, height: size * 1.18)
        }
        .onAppear { visible = true }.onDisappear { visible = false }
        .accessibilityHidden(true)
    }
}

// A solid silhouette avoids the cutout and duplicate inner flame in the SF Symbol.
private struct StreakFireContour: Shape {
    var time: Double
    func path(in rect: CGRect) -> Path {
        let rise = sin(time * 9) * 0.025 + sin(time * 15) * 0.015
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: point(0.50, 0.98))
        path.addCurve(to: point(0.12, 0.62), control1: point(0.14, 0.98), control2: point(0.02, 0.82))
        path.addCurve(to: point(0.24, 0.38 + rise), control1: point(0.14, 0.52), control2: point(0.23, 0.46))
        path.addQuadCurve(to: point(0.28, 0.59), control: point(0.22, 0.53))
        path.addCurve(to: point(0.45, 0.03 + rise), control1: point(0.51, 0.41), control2: point(0.49, 0.21))
        path.addCurve(to: point(0.79, 0.44 - rise), control1: point(0.67, 0.13), control2: point(0.74, 0.31))
        path.addQuadCurve(to: point(0.78, 0.29 - rise), control: point(0.82, 0.36))
        path.addCurve(to: point(0.50, 0.98), control1: point(1.11, 0.65), control2: point(0.94, 0.98))
        path.closeSubpath()
        return path
    }
}
