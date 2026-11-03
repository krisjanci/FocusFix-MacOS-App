import SwiftUI

// Value-only component shared by the app and isolated visual checks.
struct RecordingStatusPanel: View {
    let state: CaptureState
    let mode: RecordingMode
    let context: ActivityContext
    let phase: InterventionPhase
    var body: some View {
        Label(RecordingPresentation.status(state: state, mode: mode, context: context, phase: phase),
              systemImage: state == .recording ? "record.circle.fill" : "pause.circle")
            .font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}
