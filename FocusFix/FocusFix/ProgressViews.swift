// MARK: - FF: PROGRESS UI
import SwiftUI

struct DailyProgressCard: View {
    @ObservedObject var tracker: ActivityTracker
    @ObservedObject private var social = SocialController.shared
    var body: some View {
        // Refresh the local day even when the app is idle across midnight.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let calendar = social.enabled ? social.calendar : DailyProgress.calendar()
            let progress = social.ledger?.progress ?? tracker.dailyProgress
            let day = progress.day(at: context.date, calendar: calendar)
            let streak = progress.streak(at: context.date, calendar: calendar)
            let weekend = DailyProgress.isWeekend(context.date, calendar: calendar)
            let complete = day.workSeconds >= DailyProgress.goalSeconds
            DailyProgressDisplay(workMinutes: Int(day.workSeconds / 60), streak: streak,
                breakCount: day.completedBreakIDs.count, weekend: weekend, complete: complete,
                recharged: tracker.rechargeDate.map {
                    calendar.isDate($0, inSameDayAs: context.date) && context.date.timeIntervalSince($0) < 20
                } ?? false, notice: tracker.progressNotice, workSeconds: day.workSeconds,
                freezes: progress.tokensRemaining(at: context.date, calendar: calendar), pending: social.pendingConfirmation,
                active: tracker.isRecording && tracker.breakPhase == .work)
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
                Label("Today · \(workMinutes) / 60 min",
                      systemImage: complete ? "checkmark.circle.fill" : "target")
                    .font(.callout.weight(.medium))
                Spacer()
                if weekend { Text("Optional").font(.caption).foregroundStyle(.secondary) }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(teal.opacity(0.12))
                    Capsule().fill(teal)
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
            }.frame(height: 4)
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
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let calendar = social.enabled ? social.calendar : DailyProgress.calendar()
            let progress = social.ledger?.progress ?? tracker.dailyProgress
            let day = progress.day(at: context.date, calendar: calendar)
            let streak = progress.streak(at: context.date, calendar: calendar)
            Text("Today: \(Int(day.workSeconds / 60))/60 min · \(streak)-day weekday streak")
            Text("Breaks taken today: \(day.completedBreakIDs.count)")
        }
    }
}
