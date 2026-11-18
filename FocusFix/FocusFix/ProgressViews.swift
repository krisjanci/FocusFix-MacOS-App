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
                Label(streak > 0 ? "\(streak)-day streak" : "Start a new streak",
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
                Text("Weekends are optional. Completing today’s goal still adds a streak day.")
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
        Text("Declared work: \(Int(day.workSeconds / 60))/60 min · \(status.count)-day streak")
        Text("Breaks taken today: \(day.completedBreakIDs.count)")
    }
}

struct WorkStreakBadge: View {
    @ObservedObject var tracker: ActivityTracker
    @State private var calendarPresented = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let status = tracker.dailyProgress.streakStatus(at: context.date, calendar: DailyProgress.calendar())
            Button { calendarPresented.toggle() } label: {
                WorkStreakFlame(status: status)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Work streak, \(status.description)")
            .accessibilityHint("Open work streak calendar")
            .help("Open work streak calendar")
        }
        .popover(isPresented: $calendarPresented, arrowEdge: .bottom) {
            WorkStreakCalendar(tracker: tracker)
        }
    }
}

private struct WorkStreakCalendar: View {
    @ObservedObject var tracker: ActivityTracker
    @State private var month = Date()
    @Environment(\.dismiss) private var dismiss
    private let calendar = DailyProgress.calendar()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let today = context.date
            let progress = reconciledProgress(at: today)
            let joined = joinedDate(in: progress, fallback: today)
            let start = calendar.dateInterval(of: .month, for: month)!.start
            let dayCount = calendar.range(of: .day, in: .month, for: start)!.count
            let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Work streak").font(.headline)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Close work streak calendar")
                }
                Text("60 minutes of declared work earns a streak day.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button { moveMonth(-1, joined: joined, today: today) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous month")
                        .disabled(calendar.isDate(start, equalTo: joined, toGranularity: .month) || start < calendar.startOfDay(for: joined))
                    Spacer()
                    Text(start.formatted(.dateTime.month(.wide).year())).font(.subheadline.weight(.semibold))
                    Spacer()
                    Button { moveMonth(1, joined: joined, today: today) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next month")
                        .disabled(calendar.isDate(start, equalTo: today, toGranularity: .month))
                }
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(0..<7, id: \.self) { index in
                        let weekday = (calendar.firstWeekday - 1 + index) % 7
                        Text(calendar.shortWeekdaySymbols[weekday])
                            .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(0..<(offset + dayCount), id: \.self) { index in
                        if index < offset {
                            Color.clear.frame(height: 34).accessibilityHidden(true)
                        } else {
                            let date = calendar.date(byAdding: .day, value: index - offset, to: start)!
                            dayCell(date, progress: progress, today: today, joined: joined)
                        }
                    }
                }
                HStack(spacing: 18) {
                    HStack(spacing: 5) {
                        calendarFlame
                        Text("Goal met")
                    }
                    Label("Freeze used", systemImage: "snowflake").foregroundStyle(.blue)
                }.font(.caption)
                Label("Joined FocusFix · \(joined.formatted(date: .abbreviated, time: .omitted))", systemImage: "flag.fill")
                    .font(.caption).foregroundStyle(.teal)
                Text("Missed weekends are optional and use no freezes.")
                    .font(.caption).foregroundStyle(.secondary)
                if !calendar.isDate(start, equalTo: today, toGranularity: .month) {
                    Button("Back to this month") { month = today }.font(.caption)
                }
            }
            .padding(20).frame(width: 350)
        }
    }

    private var calendarFlame: some View {
        StreakFireContour(time: 0)
            .fill(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .bottom, endPoint: .top))
            .frame(width: 11, height: 14)
            .accessibilityHidden(true)
    }

    private func dayCell(_ date: Date, progress: DailyProgress, today: Date, joined: Date) -> some View {
        let future = calendar.startOfDay(for: date) > calendar.startOfDay(for: today)
        let beforeJoining = calendar.startOfDay(for: date) < calendar.startOfDay(for: joined)
        let isJoined = calendar.isDate(date, inSameDayAs: joined)
        let complete = !beforeJoining && !future && progress.day(at: date, calendar: calendar).workSeconds >= DailyProgress.goalSeconds
        let frozen = !beforeJoining && !future && !complete && progress.frozenDays.contains(DailyProgress.key(for: date, calendar: calendar))
        let isToday = calendar.isDate(date, inSameDayAs: today)
        let detail = beforeJoining ? "Before joining FocusFix" : complete ? "Work goal met" : frozen ? "Freeze used" : future ? "Future day" : "Work goal not met"
        return VStack(spacing: 1) {
            HStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))").monospacedDigit()
                if complete { calendarFlame }
                else if frozen { Image(systemName: "snowflake").font(.caption2).foregroundStyle(.blue) }
            }
            if isJoined {
                Text("Joined").font(.system(size: 8, weight: .semibold)).foregroundStyle(.teal)
            }
        }
        .font(.caption.weight(isToday ? .bold : .regular))
        .frame(maxWidth: .infinity).frame(height: 34)
        .foregroundStyle(future || beforeJoining ? Color.secondary.opacity(0.5) : Color.primary)
        .background(complete ? Color.orange.opacity(0.12) : frozen ? Color.blue.opacity(0.12) : isJoined ? Color.teal.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted))\(isToday ? ", today" : "")\(isJoined ? ", joined FocusFix" : ""), \(detail)")
        .help("\(date.formatted(date: .complete, time: .omitted))\(isJoined ? ": Joined FocusFix" : ""): \(detail)")
    }

    private func reconciledProgress(at date: Date) -> DailyProgress {
        var progress = tracker.dailyProgress
        progress.reconcile(at: date, calendar: calendar)
        return progress
    }

    // The local work ledger records its start on first launch, including guest use.
    private func joinedDate(in progress: DailyProgress, fallback: Date) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let firstDay = ([progress.protectionStart].compactMap { $0 } + Array(progress.days.keys)).min()
        return firstDay.flatMap { formatter.date(from: $0) } ?? calendar.startOfDay(for: fallback)
    }

    private func moveMonth(_ amount: Int, joined: Date, today: Date) {
        let start = calendar.dateInterval(of: .month, for: month)!.start
        let earliest = calendar.dateInterval(of: .month, for: joined)!.start
        let latest = calendar.dateInterval(of: .month, for: today)!.start
        if let next = calendar.date(byAdding: .month, value: amount, to: start),
           next >= earliest, next <= latest { month = next }
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
                if frozen {
                    FrozenStreakContour()
                        .fill(LinearGradient(colors: [Color(red: 0.70, green: 0.96, blue: 1),
                                                      Color(red: 0.15, green: 0.70, blue: 0.98),
                                                      Color(red: 0.12, green: 0.37, blue: 0.90)],
                                             startPoint: .bottom, endPoint: .top))
                    Path { path in
                        path.move(to: CGPoint(x: size * 0.50, y: size * 1.18 * 0.12))
                        path.addLine(to: CGPoint(x: size * 0.56, y: size * 1.18 * 0.27))
                        path.addLine(to: CGPoint(x: size * 0.71, y: size * 1.18 * 0.45))
                    }
                    .stroke(.white.opacity(0.63), style: StrokeStyle(lineWidth: max(0.7, size * 0.025),
                                                                   lineCap: .round, lineJoin: .miter))
                } else {
                    StreakFireContour(time: time)
                        .fill(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .bottom, endPoint: .top))
                        .shadow(color: .orange.opacity(0.26 + heat * 0.08), radius: 2)
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

// The same planted flame, frozen into a few sharp facets instead of an ice block.
private struct FrozenStreakContour: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: point(0.50, 0.98))
        path.addCurve(to: point(0.12, 0.65), control1: point(0.17, 0.98), control2: point(0.05, 0.83))
        path.addLine(to: point(0.08, 0.53))
        path.addLine(to: point(0.17, 0.57))
        path.addLine(to: point(0.24, 0.36))
        path.addLine(to: point(0.28, 0.58))
        path.addCurve(to: point(0.45, 0.03), control1: point(0.47, 0.41), control2: point(0.49, 0.22))
        path.addLine(to: point(0.62, 0.22))
        path.addLine(to: point(0.59, 0.25))
        path.addLine(to: point(0.79, 0.45))
        path.addLine(to: point(0.80, 0.29))
        path.addLine(to: point(0.94, 0.55))
        path.addLine(to: point(0.89, 0.58))
        path.addCurve(to: point(0.50, 0.98), control1: point(1.02, 0.80), control2: point(0.83, 0.98))
        path.closeSubpath()
        return path
    }
}
