# On-device AI planning

## Implementation

- `AIPlanningButton` is shared by the bottom project/task creation rows, the new-project form (below its name, before color), and the new-task form (below its field).
- Runtime availability uses `SystemLanguageModel.default.availability`, supported locale, and a macOS 26 availability guard. The faded button has a separate grey `info.circle`, with setup instructions, minimum OS, compatible hardware, language/model readiness guidance, and System Settings/help links. Returning to the app refreshes availability.
- `AIPlanningSpeech` asks for microphone permission only on Start speaking, records up to two minutes into a temporary CAF, then uses SpeechAnalyzer/SpeechTranscriber to transcribe locally. Cancel, failure and successful transcription remove temporary audio. Cancelling also stops recording and analysis. A speech model may download on first use. Unsupported speech locales or denied microphone access leave typing available.
- The transcript is editable before generation. `AIPlanning.generate` uses a new on-device Foundation Models session and constrained structured output for each request. It extracts only mentioned tasks, proposes concise titles, and estimates 0.5–3 FS in half-session increments. Explicit durations are requested directly in FS (one hour = one FS).
- Project mode reviews a project title, color and tasks; existing-project mode reviews only tasks and preserves that project's identity, name, color and existing tasks. Both allow title/estimate edits, task removal/addition, Back and Cancel.
- `ProjectStore.savePlan` validates the whole draft before one atomic write. Each saved task receives a new identity, creation date and predicted estimate. Failure leaves the preview and catalog intact for retry. No activity recording, assignment or cloud sharing is started by planning.
- Microphone usage text and sandbox audio-input access are included for Debug and Release. The release verifier checks both. New frameworks are weak-linked, retaining the app's macOS 14 deployment target while AI requires macOS 26.

## Verification performed

Checked on November 27, 2026 with Xcode 27.1:

- Complete Debug build passed. Complete final Release build passed (unsigned local builds, not a distribution/signing check).
- Focused `AIPlanningTests`, `ProjectsTests`, `ChecklistPageTests` and `TaskPopupLayoutTests` passed. The new checks cover project + tasks, existing-project append without rename/recolor, Random Tasks, persisted FS, unique identities, invalid titles/estimates/counts, deleted projects, unchanged disk/memory after failures, and a real filesystem write failure followed by successful retry.
- `verification/ai-planning-smoke.swift` passed using synthesized English audio through the **production** `AIPlanningSpeech.transcribeFile` path and real on-device Foundation Models generation. It transcribed three website tasks and generated **0.5, 0.5 and 2 FS**, matching the spoken durations. A second request for an existing project returned two tasks.
- Native isolated preview verified all four entry placements, project-title and task-title editing, new-project saving, tasks-only saving into Random Tasks, and adjustment of a generated 1 FS estimate to 2 FS followed by its persisted display in the checklist.
- Native light/dark layouts were visually inspected. The unavailable-state fixture rendered a disabled, faded AI button and grey info circle; its live popover exposed the setup instructions, macOS Tahoe 26 minimum, supported hardware and settings/help controls.
- The final universal Release binary weak-links FoundationModels and Speech. Its built Info.plist contains the microphone disclosure. Release entitlement/disclosure validation passed and rejected a missing disclosure. `bash -n scripts/verify-release.sh` and `git diff --check` passed.

Physical microphone input and its allow/deny OS dialogs were not exercised; the audio integration check uses synthesized audio and does not request microphone access. Fresh-machine model downloads, unsupported hardware/OS, and distribution signing remain release checks described in `RELEASE.md`. AI output is a suggestion, not a guarantee of task meaning or effort accuracy.

## Reproduce

Run the focused catalog/layout checks:

```sh
FOCUSFIX_TEST_FILTER='AIPlanningTests|ProjectsTests|ChecklistPageTests|TaskPopupLayoutTests' bash scripts/test.sh
```

Build the isolated native preview with `bash scripts/preview-projects.sh`. Open its printed app path. The Preview menu can toggle appearance and show the unavailable-state fixture. It uses temporary synthetic projects and never links the real recorder or account services.

For the real on-device speech/model smoke check on a prepared, supported Mac:

```sh
check_root=$(mktemp -d /tmp/focusfix-ai-check.XXXXXX)
say -o "$check_root/plan.aiff" 'I am redesigning my website. I need to sketch the homepage for half an hour, choose a color palette for half an hour, and build a contact form for two hours.'
xcrun swiftc -module-cache-path "$check_root/cache" \
  FocusFix/FocusFix/SessionTags.swift FocusFix/FocusFix/Projects.swift \
  FocusFix/FocusFix/AIPlanning.swift FocusFix/FocusFix/AIPlanningSpeech.swift \
  verification/ai-planning-smoke.swift -o "$check_root/check"
"$check_root/check" "$check_root/plan.aiff"
```

The model smoke check deliberately requires usable Apple Intelligence and speech assets. It does not silently pass when the model is unavailable. Generative estimates can vary; inspect a failure rather than treating it as a deterministic catalog regression.

Apple references: [Foundation Models](https://developer.apple.com/documentation/foundationmodels), [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer), [Apple Intelligence setup](https://support.apple.com/121115).
