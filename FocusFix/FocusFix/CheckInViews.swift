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
                Button(rating.map { "\($0) / 10" } ?? "Select 5 / 10") { rating = rating ?? 5 }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(rating.map { "\(title): \($0) out of 10" } ?? "Choose 5 out of 10 for \(title)")
            }
            Slider(value: Binding(get: { Double(rating ?? 5) }, set: { rating = Int($0) }), in: 0...10, step: 1)
                .accessibilityLabel(title)
                .accessibilityValue(rating.map { "\($0) out of 10" } ?? "Not answered")
            HStack {
                Button("0 · \(low)") { rating = 0 }
                Spacer()
                Button("10 · \(high)") { rating = 10 }
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
    @State private var fatigue: Int?

    // Ask for fatigue before a session, with skip and cancel choices.
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Before you start").font(.title2.weight(.semibold))
            FatigueSlider(rating: $fatigue)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Skip & start") { tracker.completeSessionCheckIn(fatigue: nil) }
                Button("Start session") { tracker.completeSessionCheckIn(fatigue: fatigue) }
                    .buttonStyle(.borderedProminent).disabled(fatigue == nil)
            }
        }.padding(28).frame(width: 440)
    }
}

struct WorkCheckInView: View {
    @ObservedObject var tracker: ActivityTracker
    @State private var fatigue: Int?
    @State private var productivity: Int?

    // Ask for fatigue and self-reported productivity during work without guessing unanswered values.
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Check-in").font(.title2.weight(.semibold))
            FatigueSlider(rating: $fatigue)
            RatingSlider(title: SurveyEntry.productivityQuestion,
                low: "Not productive", high: "Extremely productive", rating: $productivity)
            HStack {
                Button("Skip") { tracker.skipTimedCheckIn() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    guard let fatigue, let productivity else { return }
                    tracker.completeTimedCheckIn(fatigue: fatigue, productivity: productivity)
                }.buttonStyle(.borderedProminent).disabled(fatigue == nil || productivity == nil)
            }
        }.padding(28).frame(width: 440)
    }
}
