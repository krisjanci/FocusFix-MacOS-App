import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var tracker: ActivityTracker
    @ObservedObject private var plan = SessionWorkPlanPreferences.shared
    @State private var expanded = false
    @State private var preview = false
    @State private var custom = false
    @State private var customMinutes = "60"

    private var invalidCustom: Bool {
        custom && (Int(customMinutes).map { !(1...480).contains($0) } ?? true)
    }

    var body: some View {
        DisclosureGroup("Advanced", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Use a session work target", isOn: $plan.enabled)
                if plan.enabled {
                    Picker("Work target", selection: Binding(get: {
                        custom ? 0 : plan.minutes
                    }, set: { value in
                        custom = value == 0
                        if custom { customMinutes = String(plan.minutes) }
                        else { plan.setMinutes(value) }
                    })) {
                        Text("30 min").tag(30)
                        Text("60 min").tag(60)
                        Text("90 min").tag(90)
                        Text("Custom").tag(0)
                    }
                    if custom {
                        HStack {
                            TextField("Minutes", text: $customMinutes)
                                .textFieldStyle(.roundedBorder).frame(width: 80)
                                .accessibilityLabel("Custom session work target in minutes")
                                .onChange(of: customMinutes) { _, value in
                                    if let minutes = Int(value) { plan.setMinutes(minutes) }
                                }
                            Text("minutes · 1–480").font(.caption).foregroundStyle(.secondary)
                        }
                        if invalidCustom {
                            Text("Enter a whole number from 1 to 480. The saved target is \(plan.minutes) minutes.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Counts work, including quiet reading. Breaks and check-ins do not count. You'll choose when to stop.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Changes apply to your next session.").font(.caption).foregroundStyle(.secondary)
                Divider()
                Button("Preview welcome screen") { preview = true }
                    .disabled(tracker.isRecording)
                Text(tracker.isRecording ? "Stop recording to preview the account screens." : "Explore Create account and Log in without changing your account or deleting history.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 8)
        }
        .onAppear {
            custom = ![30, 60, 90].contains(plan.minutes)
            customMinutes = String(plan.minutes)
        }
        .sheet(isPresented: $preview) { WelcomePreviewView() }
        .onChange(of: tracker.isRecording) { _, recording in if recording { preview = false } }
    }
}
