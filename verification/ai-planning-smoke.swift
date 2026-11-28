// Uses only the synthetic audio path supplied on the command line.
// Runs the same SpeechAnalyzer path used after microphone capture, then the real
// on-device planning model. No recorder, account, or real catalog is linked.
import Foundation
import Speech

@available(macOS 26.0, *)
@main @MainActor struct AIPlanningSmoke {
    static func main() async throws {
        if let reason = AIPlanning.unavailableReason { throw SessionTags.TagError(reason) }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            throw SessionTags.TagError("English transcription is unavailable on this Mac")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        let speech = AIPlanningSpeech()
        let transcript = try await speech.transcribeFile(URL(fileURLWithPath: CommandLine.arguments[1]), using: transcriber)
        precondition(transcript.lowercased().contains("homepage"))
        print("Synthetic audio transcript: \(transcript)")
        let plan = try await AIPlanning.generate(transcript: transcript, projectName: nil)
        precondition(!plan.title.isEmpty && plan.tasks.count == 3)
        precondition(plan.tasks.contains { $0.focusSessions == "2" }, "The stated two-hour task should receive 2 FS")
        for task in plan.tasks {
            try ProjectTask.validateEstimate(Double(task.focusSessions)!)
            print("\(task.title): \(task.focusSessions) FS")
        }
        let existing = try await AIPlanning.generate(transcript: "In this project, review the layout for half an hour and test the form for one hour.", projectName: "Website Refresh")
        precondition(existing.tasks.count == 2)
        print("Existing-project mode generated \(existing.tasks.count) tasks")
        print("On-device audio → transcript → structured plan smoke check passed")
    }
}
