// MARK: - FF: PROGRESS UI
import SwiftUI

struct DailyProgressCard: View {
    @ObservedObject var tracker: ActivityTracker
    var body: some View {
        // Refresh the local day even when the app is idle across midnight.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let calendar = DailyProgress.calendar()
            let day = tracker.dailyProgress.day(at: context.date, calendar: calendar)
            let streak = tracker.dailyProgress.streak(at: context.date, calendar: calendar)
            let weekend = DailyProgress.isWeekend(context.date, calendar: calendar)
            let complete = day.workSeconds >= DailyProgress.goalSeconds
            DailyProgressDisplay(workMinutes: Int(day.workSeconds / 60), streak: streak,
                breakCount: day.completedBreakIDs.count, weekend: weekend, complete: complete,
                recharged: tracker.rechargeDate.map {
                    calendar.isDate($0, inSameDayAs: context.date) && context.date.timeIntervalSince($0) < 20
                } ?? false, notice: tracker.progressNotice, workSeconds: day.workSeconds)
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
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Today · \(workMinutes) / 60 min",
                      systemImage: complete ? "checkmark.circle.fill" : "target")
                    .font(.callout.weight(.medium))
                Spacer()
                if weekend { Text("Optional").font(.caption).foregroundStyle(.secondary) }
            }
            ProgressView(value: min(workSeconds, 3600), total: 3600)
                .tint(teal)
                .accessibilityLabel("Daily work goal")
                .accessibilityValue("\(workMinutes) of 60 minutes")
            HStack {
                Label(streak > 0 ? "\(streak)-day weekday streak" : "Start a new streak",
                      systemImage: "flame")
                Spacer()
                Label("Breaks taken today: \(breakCount)", systemImage: "leaf")
            }
            .font(.caption).foregroundStyle(.secondary)
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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let calendar = DailyProgress.calendar()
            let day = tracker.dailyProgress.day(at: context.date, calendar: calendar)
            let streak = tracker.dailyProgress.streak(at: context.date, calendar: calendar)
            Text("Today: \(Int(day.workSeconds / 60))/60 min · \(streak)-day weekday streak")
            Text("Breaks taken today: \(day.completedBreakIDs.count)")
        }
    }
}
