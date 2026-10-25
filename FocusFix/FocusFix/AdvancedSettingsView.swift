import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var tracker: ActivityTracker
    @State private var expanded = false
    @State private var preview = false
    var body: some View {
        DisclosureGroup("Advanced", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Button("Preview welcome screen") { preview = true }
                    .disabled(tracker.isRecording)
                Text(tracker.isRecording ? "Stop recording to preview the account screens." : "Explore Create account and Log in without changing your account or deleting history.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 8)
        }
        .sheet(isPresented: $preview) { WelcomePreviewView() }
        .onChange(of: tracker.isRecording) { _, recording in if recording { preview = false } }
    }
}
