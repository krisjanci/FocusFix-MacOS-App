// MARK: - FF: SURVEYS
// Displays simple ratings. A slider's initial middle position is not an answer until the user chooses it.

import SwiftUI

struct RatingSlider: View {
    let title: String
    let low: String
    let high: String
    @Binding var rating: Int?

    // Render a 0–10 slider with explicit selection and readable endpoint buttons.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                // The thumb starts in the middle, but no answer is selected yet.
                // This button also lets someone select exactly 5 without dragging.
                Button(rating.map { "\($0) / 10" } ?? "Select 5 / 10") { rating = rating ?? 5 }.buttonPressFeedback()
                    .buttonStyle(.bordered)
                    .accessibilityLabel(rating.map { "\(title): \($0) out of 10" } ?? "Choose 5 out of 10 for \(title)")
            }
            Slider(value: Binding(get: { Double(rating ?? 5) }, set: { rating = Int($0) }), in: 0...10, step: 1)
                .accessibilityLabel(title)
                .accessibilityValue(rating.map { "\($0) out of 10" } ?? "Not answered")
            HStack {
                Button("0 · \(low)") { rating = 0 }.buttonPressFeedback()
                Spacer()
                Button("10 · \(high)") { rating = 10 }.buttonPressFeedback()
            }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct FatigueSlider: View {
    @Binding var rating: Int?
    // Reuse the standard slider with the mental-fatigue question and anchors.
    var body: some View {
        RatingSlider(title: SurveyEntry.fatigueQuestion,
            low: "Not tired", high: "Extremely tired", rating: $rating)
    }
}

struct SessionCheckInView: View {
    @ObservedObject var tracker: ActivityTracker
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SessionStartDraft
    @State private var notice: String?
    @Namespace private var targetSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var minutesFocused: Bool
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    init(tracker: ActivityTracker) {
        self.tracker = tracker
        _draft = State(initialValue: SessionStartDraft.workTarget(
            asksForFatigue: !tracker.isWorking && tracker.sessionSurveyOptions.beforeSession,
            targetMinutes: tracker.timerTargetMinutes))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Work target").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Give your next stretch of work a little direction.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if draft.asksForFatigue { FatigueSlider(rating: $draft.fatigue) }
            if draft.planning {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 4) {
                        ForEach([30, 60, 90, 0], id: \.self) { choice in
                            Button {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                    draft.durationChoice = choice
                                }
                                minutesFocused = choice == 0
                            } label: {
                                Text(choice == 0 ? "Custom" : "\(choice) min")
                                    .font(.callout.weight(.semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .foregroundStyle(draft.durationChoice == choice ? Color.white : Color.primary)
                                    .background {
                                        if draft.durationChoice == choice {
                                            RoundedRectangle(cornerRadius: 10).fill(teal)
                                                .matchedGeometryEffect(id: "target", in: targetSelection)
                                        }
                                    }
                                    .contentShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                                .accessibilityLabel(choice == 0 ? "Custom duration" : "\(choice) minutes")
                                .accessibilityAddTraits(draft.durationChoice == choice ? .isSelected : [])
                        }
                    }.padding(4).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityElement(children: .contain).accessibilityLabel("Target duration")
                    if draft.durationChoice == 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("How many minutes would you like to work?").font(.callout.weight(.medium))
                            HStack {
                                TextField("Enter minutes", text: $draft.customMinutes)
                                    .textFieldStyle(.roundedBorder).frame(width: 120)
                                    .focused($minutesFocused)
                                    .accessibilityLabel("Work target minutes")
                                Text("minutes · 1–480").font(.caption).foregroundStyle(.secondary)
                            }
                            if !draft.validPlan {
                                Text("Enter a whole number from 1 to 480.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Label {
                        Text("Work time includes quiet reading. Breaks and check-ins don't count. You choose when to stop.")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: { Image(systemName: "info.circle") }
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(18).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
            }
            if !draft.planning { Button("Add work target") { draft.addPlan() }.buttonPressFeedback() }
            if tracker.isWorking, draft.planning {
                Button("Remove target") { draft.removePlan() }.buttonPressFeedback()
            }
            if let notice { Text(notice).font(.callout).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.buttonPressFeedback().keyboardShortcut(.cancelAction)
                Spacer()
                if draft.asksForFatigue {
                    Button("Skip & start work") { start(skippingFatigue: true) }.buttonPressFeedback()
                        .disabled(!draft.validPlan)
                }
                Button(tracker.isWorking ? "Done" : "Start work") { start() }.buttonPressFeedback()
                    .buttonStyle(.borderedProminent).disabled(draft.selection() == nil)
            }
        }.padding(28).frame(width: 440).tint(teal)
    }

    private func start(skippingFatigue: Bool = false) {
        guard let selection = draft.selection(skippingFatigue: skippingFatigue) else { return }
        do { try tracker.completeSessionCheckIn(selection) }
        catch { notice = error.localizedDescription }
    }
}

struct WorkCheckInView: View {
    @ObservedObject var tracker: ActivityTracker
    @State private var fatigue: Int?
    @State private var productivity: Int?

    // Ask for fatigue and self-reported productivity during work without guessing unanswered values.
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Optional check-in").font(.title2.weight(.semibold))
            if let recall = tracker.studyRecallDescription { Text(recall).font(.callout).foregroundStyle(.secondary) }
            FatigueSlider(rating: $fatigue)
            RatingSlider(title: SurveyEntry.productivityQuestion,
                low: "Not productive", high: "Extremely productive", rating: $productivity)
            HStack {
                Button("Skip") { tracker.skipTimedCheckIn() }.buttonPressFeedback().keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    guard let fatigue, let productivity else { return }
                    tracker.completeTimedCheckIn(fatigue: fatigue, productivity: productivity)
                }.buttonPressFeedback().buttonStyle(.borderedProminent).disabled(fatigue == nil || productivity == nil)
            }
        }.padding(28).frame(width: 440)
    }
}
