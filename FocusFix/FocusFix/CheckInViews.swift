import SwiftUI

struct RatingSlider: View {
    let title: String
    let question: String
    let explanation: String
    let low: String
    let high: String
    @Binding var rating: Int?

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
            Text(question).font(.callout).fixedSize(horizontal: false, vertical: true)
            Text(explanation).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Slider(value: Binding(get: { Double(rating ?? 5) }, set: { rating = Int($0) }), in: 0...10, step: 1)
                .accessibilityLabel(question)
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
    var body: some View {
        RatingSlider(title: "Mental fatigue", question: SurveyEntry.fatigueQuestion,
            explanation: "Think about how tired your mind feels, not how hard the task is.",
            low: "Not tired", high: "Extremely tired", rating: $rating)
    }
}

struct SessionCheckInView: View {
    @ObservedObject var tracker: ActivityTracker
    @Environment(\.dismiss) private var dismiss
    @State private var fatigue: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Before you start").font(.title2.weight(.semibold))
            Text("A quick check-in. There is no right or wrong answer.")
                .font(.callout).foregroundStyle(.secondary)
            FatigueSlider(rating: $fatigue)
            Text("Move the slider or select a number. Your session timer starts after this check-in.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
