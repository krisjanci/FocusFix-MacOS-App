import SwiftUI

func durationText(_ seconds: Double) -> String {
    let value = Int(max(0, seconds).rounded(.up))
    return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
}

struct BreakActivityPicker: View {
    static let options = ["Stretch", "Walk", "Water / snack", "Rest my eyes", "Breathing", "Other"]
    @Binding var selection: String
    @Binding var custom: String
    var body: some View {
        Picker("Activity", selection: $selection) {
            ForEach(Self.options, id: \.self) { Text($0).tag($0) }
        }
        if selection == "Other" {
            TextField("What would you like to do?", text: $custom)
                .textFieldStyle(.roundedBorder)
                .onChange(of: custom) { _, value in custom = String(value.prefix(120)) }
        }
    }
}

struct BreakSetupView: View {
    @ObservedObject var tracker: ActivityTracker
    @Environment(\.dismiss) private var dismiss
    @State private var preset = 5
    @State private var customMinutes = "5"
    @State private var activity = "Stretch"
    @State private var customActivity = ""
    @State private var fatigue: Int?
    @State private var workload: Int?
    private var minutes: Double? { preset == 0 ? Double(customMinutes.replacingOccurrences(of: ",", with: ".")) : Double(preset) }
    private var label: String { (activity == "Other" ? customActivity : activity).trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool { minutes.map { $0.isFinite && (1...120).contains($0) } == true && !label.isEmpty }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            Label("Make time for a break", systemImage: "leaf").font(.title2.weight(.semibold))
            Text("Before you step away, a quick check-in.").foregroundStyle(.secondary)
            FatigueSlider(rating: $fatigue)
            RatingSlider(title: "Mental workload", question: SurveyEntry.workloadQuestion,
                explanation: "Think about how much thinking, focus or effort your work needed—not how tired you feel.",
                low: "Not demanding", high: "Extremely demanding", rating: $workload)
            Text("Move each slider or select a number. There is no right or wrong answer.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Choose a duration and what you feel like doing.").foregroundStyle(.secondary)
            Picker("Duration", selection: $preset) {
                Text("5 min").tag(5)
                Text("10 min").tag(10)
                Text("15 min").tag(15)
                Text("Custom").tag(0)
            }.pickerStyle(.segmented)
            if preset == 0 {
                HStack {
                    TextField("Minutes", text: $customMinutes).textFieldStyle(.roundedBorder).frame(width: 90)
                    Text("minutes · 1–120").foregroundStyle(.secondary)
                }
            }
            BreakActivityPicker(selection: $activity, custom: $customActivity)
            Text("Detailed tracking pauses during your break. Use “I'm back” or return to another app to finish early.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start break") {
                    guard let minutes, valid else { return }
                    tracker.beginBreak(minutes: minutes, activity: label, fatigue: fatigue, workload: workload)
                }.buttonStyle(.borderedProminent).disabled(!valid || fatigue == nil || workload == nil)
            }
            Button("Skip ratings & start break") {
                guard let minutes, valid else { return }
                tracker.beginBreak(minutes: minutes, activity: label, fatigue: nil, workload: nil)
            }.disabled(!valid).font(.callout)
        }.padding(28)
        }.frame(width: 480, height: 650)
    }
}

struct BreakReviewView: View {
    @ObservedObject var tracker: ActivityTracker
    let record: BreakRecord
    @Environment(\.dismiss) private var dismiss
    @State private var activity = "Stretch"
    @State private var custom = ""
    private var label: String { (activity == "Other" ? custom : activity).trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What did you do?").font(.title2.weight(.semibold))
            Text("Planned: \(record.plannedActivity)").foregroundStyle(.secondary)
            Text("Break length: \(durationText(record.actualSeconds ?? 0))").monospacedDigit()
            BreakActivityPicker(selection: $activity, custom: $custom)
            HStack {
                Button("Later") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save activity") {
                    tracker.confirmBreakActivity(label)
                    dismiss()
                }.buttonStyle(.borderedProminent).disabled(label.isEmpty || !tracker.isRecording)
            }
        }.padding(28).frame(width: 400)
        .onAppear {
            let value = record.actualActivity.isEmpty ? record.plannedActivity : record.actualActivity
            activity = BreakActivityPicker.options.contains(value) ? value : "Other"
            custom = activity == "Other" ? value : ""
        }
    }
}

struct BreakControls: View {
    @ObservedObject var tracker: ActivityTracker
    @State private var reviewing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tracker.breakPromptPending {
                Text("A moment for a break?").font(.headline)
                HStack {
                    Button("Take a break") { tracker.chooseBreak() }.buttonStyle(.borderedProminent)
                    Button("Skip") { tracker.deferBreak(snooze: false) }.help("Wait 25 more minutes, then look for an idle moment")
                    Button("Snooze 10 min") { tracker.deferBreak(snooze: true) }
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tracker.latestBreak == nil ? "Since session start" : "Since last break")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(durationText(tracker.secondsSinceBreak)).monospacedDigit()
                    }
                    Spacer()
                    Button("Take a break") { tracker.chooseBreak() }
                }
            }
            if let last = tracker.latestBreak {
                HStack {
                    Text("Last break · \(durationText(last.actualSeconds ?? 0))")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(last.actualActivity.isEmpty ? "Confirm activity" : "Edit activity") { reviewing = true }
                        .font(.caption)
                }
            }
            if let notice = tracker.notificationNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $reviewing) {
            if let last = tracker.latestBreak { BreakReviewView(tracker: tracker, record: last) }
        }
    }
}
