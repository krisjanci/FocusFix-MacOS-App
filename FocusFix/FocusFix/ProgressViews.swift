// MARK: - FF: PROGRESS UI
import SwiftUI

struct DailyProgressCard: View {
    @ObservedObject var tracker: ActivityTracker
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    var body: some View {
        // Refresh the local day even when the app is idle across midnight.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let calendar = DailyProgress.calendar()
            let day = tracker.dailyProgress.day(at: context.date, calendar: calendar)
            let streak = tracker.dailyProgress.streak(at: context.date, calendar: calendar)
            let weekend = DailyProgress.isWeekend(context.date, calendar: calendar)
            let complete = day.workSeconds >= DailyProgress.goalSeconds
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Today · \(Int(day.workSeconds / 60)) / 60 min",
                          systemImage: complete ? "checkmark.circle.fill" : "target")
                        .font(.callout.weight(.medium))
                    Spacer()
                    if weekend { Text("Optional").font(.caption).foregroundStyle(.secondary) }
                }
                ProgressView(value: min(day.workSeconds, DailyProgress.goalSeconds), total: DailyProgress.goalSeconds)
                    .tint(teal)
                    .accessibilityLabel("Daily work goal")
                    .accessibilityValue("\(Int(day.workSeconds / 60)) of 60 minutes")
                HStack {
                    Label(streak > 0 ? "\(streak)-day weekday streak" : "Start a new streak",
                          systemImage: "flame")
                    Spacer()
                    Label("Breaks taken today: \(day.completedBreakIDs.count)", systemImage: "leaf")
                }
                .font(.caption).foregroundStyle(.secondary)
                if complete {
                    Text("Daily goal complete. Nice work!").font(.caption).foregroundStyle(teal)
                }
                if let date = tracker.rechargeDate,
                   calendar.isDate(date, inSameDayAs: context.date),
                   context.date.timeIntervalSince(date) < 20 {
                    Text("You made time to recharge.").font(.caption).foregroundStyle(teal)
                }
                if weekend {
                    Text("Weekends are optional. Your weekday streak takes a break too.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let notice = tracker.progressNotice {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
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
