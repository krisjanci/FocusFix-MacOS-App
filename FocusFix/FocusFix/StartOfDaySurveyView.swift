import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct StartOfDaySurveyView: View {
    @ObservedObject var survey: StartOfDayController
    @State private var bedtime = Calendar.current.date(byAdding: .hour, value: -8, to: Date())!
    @State private var wakeTime = Date()
    @State private var rested: Int?
    @State private var fatigue: Int?
    @State private var stress: Int?
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "sun.horizon.fill").font(.system(size: 26)).foregroundStyle(teal)
                    Text("Start of day").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("A little context for the day ahead.").font(.callout).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your latest sleep").font(.headline)
                    DatePicker("Went to bed", selection: $bedtime, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Woke up", selection: $wakeTime, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    Text("Time in bed, not measured sleep. Adjust both dates for overnight or daytime sleep.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(16).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                RatingSlider(title: "How rested do you feel?", low: "Not at all", high: "Fully rested", rating: $rested)
                RatingSlider(title: "Mental fatigue", low: "None", high: "Extreme", rating: $fatigue)
                RatingSlider(title: "Stress right now", low: "None", high: "Extreme", rating: $stress)
                if let error = survey.error { Text(error).font(.caption).foregroundStyle(.red) }
                Text("Optional · Saved on this Mac. Export or delete in Privacy & Data Sharing.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Skip today") { survey.finish(skipping: true) }
                        .buttonPressFeedback().keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Save check-in") {
                        survey.finish(bedtime: bedtime, wakeTime: wakeTime, rested: rested, fatigue: fatigue, stress: stress)
                    }.buttonPressFeedback().buttonStyle(.borderedProminent)
                        .disabled(rested == nil || fatigue == nil || stress == nil || bedtime >= wakeTime || wakeTime > Date() || wakeTime.timeIntervalSince(bedtime) > 24 * 3600)
                }
            }.padding(26).frame(maxWidth: 480).frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(teal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Start of day survey")
    }
}

struct StartOfDaySurveySettings: View {
    @ObservedObject private var survey = StartOfDayController.shared
    @State private var confirmingDeletion = false
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Start of day survey", isOn: Binding(get: { survey.enabled }, set: { survey.setEnabled($0) }))
            Text("Once each day when you open FocusFix, including automatic launches. A short, optional check-in on sleep, restedness, fatigue and stress. Works without recording or an account.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Off by default. Responses stay on this Mac and are not included in recording uploads. Export timestamps to compare with activity and check-ins; predictions are not available yet. Turning this off keeps saved responses.")
                .font(.caption).foregroundStyle(.secondary)
            if !survey.entries.isEmpty {
                HStack {
                    Button("Export daily surveys…", action: export).buttonPressFeedback()
                    Button("Delete daily surveys…", role: .destructive) { confirmingDeletion = true }.buttonPressFeedback()
                }
            }
            if let error = survey.error {
                Text(error).font(.caption).foregroundStyle(.red)
                Button("Retry loading") { survey.reload() }.buttonPressFeedback()
            }
            if let exportError { Text(exportError).font(.caption).foregroundStyle(.red) }
        }
        .confirmationDialog("Delete all daily survey responses from this Mac?", isPresented: $confirmingDeletion) {
            Button("Delete daily surveys", role: .destructive) { survey.deleteResponses() }
        } message: { Text("This cannot be undone. Exported copies are separate. You won't be prompted again today.") }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "FocusFix-daily-surveys.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try StartOfDayStore.csv(survey.entries).write(to: url, atomically: true, encoding: .utf8)
            exportError = nil
        } catch { exportError = "Couldn’t export daily surveys. \(error.localizedDescription)" }
    }
}
