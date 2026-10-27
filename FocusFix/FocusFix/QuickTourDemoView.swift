import SwiftUI

// Only value-driven presentation components are used here, never live app controllers.
struct QuickTourDemoView: View {
    @ObservedObject var tour: QuickTourController
    let reduceMotion: Bool
    var nameFocus: FocusState<Bool>.Binding
    @State private var leafRaised = false
    @State private var feedbackReady = false
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    var body: some View {
        Group {
            switch tour.phase {
            case .plan, .duration, .confirmStart: planning
            case .startBreak: breakSetup
            case .returned: resting
            case .savedSession: library
            case .editName, .name: profile
            case .groups, .rankings, .freezes: socialPractice
            default: dashboard
            }
        }
        .id(scene)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: scene)
        .task(id: "\(tour.visit)-\(tour.phase)-\(reduceMotion)") {
            feedbackReady = false
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.2)) { feedbackReady = true }
            leafRaised = false
            if tour.phase == .returned && !reduceMotion {
                withAnimation(.easeOut(duration: 0.25)) { leafRaised = true }
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) { leafRaised = false }
            }
        }
    }

    // Keep related actions in the same scene so controls do not jump between clicks.
    private var scene: String {
        switch tour.phase {
        case .plan, .duration, .confirmStart: return "planning"
        case .startBreak: return "breakSetup"
        case .returned: return "resting"
        case .savedSession: return "library"
        case .editName, .name: return "profile"
        case .groups, .rankings, .freezes: return "social"
        default: return "dashboard"
        }
    }

    private var dashboard: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                practiceButton("Profile", symbol: "person.crop.circle", phase: .profile, action: .profile)
                    .labelStyle(.iconOnly).controlSize(.large)
                Text("FocusFix").font(.system(size: 25, weight: .semibold, design: .rounded))
                Spacer()
                Label(tour.saved || tour.phase == .start ? "Idle" : "Recording", systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SessionClockFace(time: String(format: "00:00:%02d", tour.elapsed))
                .contentTransition(.numericText())
                .padding(22).frame(maxWidth: .infinity)
                .background(teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                .practiceTarget(.work)
            DailyProgressDisplay(workMinutes: tour.dailyMinutes, streak: 2, breakCount: tour.breaks,
                complete: tour.dailyMinutes == 60, workSeconds: Double(tour.dailyMinutes * 60))
                .practiceTarget(.progress)
            HStack {
                Label(tour.breaks == 0 ? "Make time for a break" : "You made time to recharge.",
                      systemImage: tour.breaks == 0 ? "leaf" : "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
                    .scaleEffect(tour.breaks > 0 && !reduceMotion && !feedbackReady ? 0.9 : 1)
                Spacer()
                practiceButton("Take a break", phase: .takeBreak, action: .takeBreak)
            }
            HStack {
                if tour.phase == .start || tour.saved {
                    practiceButton("Start session", symbol: "record.circle", phase: .start, action: .start)
                } else {
                    practiceButton("Stop & save", symbol: "stop.fill", phase: .save, action: .save)
                }
                practiceButton("Sessions", symbol: "folder", phase: .sessions, action: .sessions)
                Spacer(minLength: 0)
            }.controlSize(.large)
            if tour.saved {
                Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(teal)
                    .scaleEffect(reduceMotion || feedbackReady ? 1 : 0.8)
                    .opacity(reduceMotion || feedbackReady ? 1 : 0)
            }
        }
    }

    private var socialPractice: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Practice group", systemImage: "person.2").font(.title2.weight(.semibold))
            if tour.phase == .groups {
                Text("Create a group or enter a shared invite code. Only members see your name, standard avatar and scores.")
                HStack {
                    practiceButton("Create group", symbol: "plus", phase: .groups, action: .createGroup)
                    Spacer()
                    practiceButton("Join with code", phase: .groups, action: .joinGroup)
                }
                    .padding(14).background(teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                Text("Practice code: ALEX-DEMO").font(.caption.monospaced()).foregroundStyle(.secondary)
            } else if tour.phase == .rankings {
                Text("Work: 60 minutes across sessions earns one daily point. Healthy habits: completing a one-minute break earns one daily point.")
                HStack { Text("Work · All time"); Spacer(); Text("Healthy habits · All time") }.font(.headline)
                HStack { Text("1  Alex"); Spacer(); Text("4 days"); Spacer(); Text("3 days") }
                HStack { Text("2  Sam"); Spacer(); Text("2 days"); Spacer(); Text("2 days") }
                Text("Scores start when you join. Weekends can earn points too.").font(.caption).foregroundStyle(.secondary)
            } else {
                Label("2 / 3 freezes remaining", systemImage: "snowflake").font(.headline).foregroundStyle(teal)
                Text("Monday: goal met → Tuesday: frozen → Wednesday: goal met")
                Text("A freeze preserves your streak without adding a day or points. Three tokens refill each month, without rollover. They cannot cover consecutive calendar dates. Weekends remain optional.")
            }
        }.fixedSize(horizontal: false, vertical: true).padding(16).practiceTarget(tour.phase)
    }

    private var planning: some View {
        let visit = tour.visit
        return VStack(alignment: .leading, spacing: 24) {
            Text("Before you start").font(.title2.weight(.semibold))
            if tour.phase == .plan {
                practiceButton("Plan session", phase: .plan, action: .plan)
            } else {
                Text("Plan session").font(.headline)
                HStack(spacing: 12) {
                    ForEach([30, 60, 90], id: \.self) { value in
                        Button("\(value) min") {
                            tour.perform(.minutes(value), phase: .duration, visit: visit)
                        }.buttonStyle(.bordered)
                            .tint(tour.phase == .confirmStart && tour.minutes == value ? teal : .secondary)
                            .disabled(tour.phase != .duration)
                    }
                }.practiceTarget(.duration)
            }
            HStack {
                Spacer()
                practiceButton("Start session", phase: .confirmStart, action: .confirmStart)
                    .buttonStyle(.borderedProminent)
            }
        }.padding(20)
    }

    private var breakSetup: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label("Make time for a break", systemImage: "leaf").font(.title2.weight(.semibold))
            HStack {
                Label("5 min", systemImage: "clock")
                Spacer()
                Text("Stretch")
            }.padding(16).background(teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Spacer()
                practiceButton("Start break", phase: .startBreak, action: .startBreak)
                    .buttonStyle(.borderedProminent)
            }
        }.padding(20)
    }

    private var resting: some View {
        VStack(spacing: 24) {
            Image(systemName: "leaf.fill").font(.system(size: 50, weight: .light)).foregroundStyle(teal)
                .scaleEffect(leafRaised ? 1.12 : 1).rotationEffect(.degrees(leafRaised ? -8 : 0))
                .accessibilityHidden(true)
            Text("TIME TO UNWIND").font(.caption).tracking(2).foregroundStyle(.secondary)
            Text("05:00").font(.system(size: 46, weight: .light, design: .rounded)).monospacedDigit()
            Text("Stretch").font(.headline)
            practiceButton("I’m back", phase: .returned, action: .returned).controlSize(.large)
                .buttonStyle(.borderedProminent)
        }.padding(24).frame(maxWidth: .infinity)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Your sessions").font(.title2.weight(.semibold))
            HStack(spacing: 14) {
                Image(systemName: "doc.text").font(.title2).foregroundStyle(teal)
                Text("Practice session").font(.headline)
                Spacer()
                Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(teal)
                    .scaleEffect(reduceMotion || feedbackReady ? 1 : 0.8)
                    .opacity(reduceMotion || feedbackReady ? 1 : 0)
            }.padding(18).background(teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                .practiceTarget(.savedSession)
        }
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Your profile").font(.title2.weight(.semibold))
            HStack(spacing: 14) {
                ProfileAvatar(profile: UserProfile(name: tour.demoName), size: 62)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill").font(.caption).foregroundStyle(.white)
                            .padding(6).background(teal, in: Circle()).accessibilityHidden(true)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    if tour.phase == .name {
                        TextField("Display name", text: Binding(get: { tour.demoName }, set: { tour.editName($0) }))
                            .textFieldStyle(.roundedBorder).font(.headline).focused(nameFocus)
                            .accessibilityLabel("Practice display name").practiceTarget(.name)
                    } else {
                        practiceButton(tour.demoName, phase: .editName, action: .editName)
                            .buttonStyle(.plain).font(.headline)
                    }
                    Text("Name and photo").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }.padding(12)
    }

    @ViewBuilder private func practiceButton(_ title: String, symbol: String? = nil,
                                            phase: QuickTourPhase, action: QuickTourAction) -> some View {
        let visit = tour.visit
        let button = Button {
            tour.perform(action, phase: phase, visit: visit)
        } label: {
            if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
        }
        Group {
            if tour.phase == phase { button.keyboardShortcut(.defaultAction) }
            else { button.disabled(true) }
        }.practiceTarget(phase)
    }
}
