import Foundation
import Combine
import AVFoundation
import Speech

/// Audio exists only in a temporary file while this sheet is open. SpeechAnalyzer
/// transcribes locally; no audio or transcript enters the activity recorder.
@available(macOS 26.0, *)
@MainActor final class AIPlanningSpeech: ObservableObject {
    @Published var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = false
    @Published private(set) var status = ""
    @Published var error: String?
    private var recorder: AVAudioRecorder?
    private var audioURL: URL?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var limitTask: Task<Void, Never>?
    private var operation = UUID()

    func start() async {
        guard !isRecording, !isBusy else { return }
        let token = UUID(); operation = token
        error = nil; isBusy = true; status = "Preparing microphone…"
        defer { if operation == token { isBusy = false } }
        do {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw SessionTags.TagError("Microphone access is off. Enable FocusFix in System Settings → Privacy & Security → Microphone, or type your plan below.")
            }
            try check(token)
            guard SpeechTranscriber.isAvailable,
                  let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
                throw SessionTags.TagError("On-device transcription is unavailable for this language. You can type your plan below.")
            }
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            status = "Preparing on-device transcription… The first use may download a speech model."
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await installation.downloadAndInstall()
            }
            try check(token)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("focusfix-voice-\(UUID()).caf")
            audioURL = url
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false
            ])
            guard recorder.record() else { throw SessionTags.TagError("The microphone could not start. Check your input device in System Settings → Sound.") }
            self.transcriber = transcriber; self.recorder = recorder
            isRecording = true; status = "Listening… Describe your work, then choose Stop."
            limitTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(120)) } catch { return }
                guard let self, self.operation == token else { return }
                await self.finish()
            }
        } catch {
            guard operation == token else { return }
            removeAudio(); self.error = error.localizedDescription; status = ""
        }
    }

    func finish() async {
        guard isRecording, let url = audioURL, let transcriber else { return }
        let token = operation
        // Do not cancel the timeout task from inside itself: finalization must finish.
        recorder?.stop(); recorder = nil; isRecording = false
        isBusy = true; status = "Transcribing on your Mac…"
        defer {
            if operation == token {
                isBusy = false; status = ""; analyzer = nil; self.transcriber = nil; removeAudio()
            }
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        let results = Task { () throws -> String in
            var parts: [String] = []
            for try await result in transcriber.results {
                try Task.checkCancellation()
                parts.append(String(result.text.characters))
            }
            return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do {
            let file = try AVAudioFile(forReading: url)
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
            let text = try await results.value
            try check(token)
            guard !text.isEmpty else { throw SessionTags.TagError("No speech was detected. Try again or type your plan below.") }
            transcript = [transcript.trimmingCharacters(in: .whitespacesAndNewlines), text].filter { !$0.isEmpty }.joined(separator: "\n")
        } catch {
            results.cancel()
            await analyzer.cancelAndFinishNow()
            if operation == token { self.error = error.localizedDescription }
        }
    }

    func cancel() {
        operation = UUID()
        limitTask?.cancel(); limitTask = nil
        recorder?.stop(); recorder = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil; transcriber = nil
        isRecording = false; isBusy = false; status = ""
        removeAudio()
    }

    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard operation == token else { throw CancellationError() }
    }

    private func removeAudio() {
        if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
        audioURL = nil
    }
}
