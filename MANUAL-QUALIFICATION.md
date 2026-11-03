# Signed fresh-Mac qualification — unperformed

November 2, 2026. Every item below is **unperformed** in this redesign. Use a stable
signed app with a recorded source revision, OS/hardware and test identity. Local
synthetic tests, unsigned builds and component images do not satisfy these checks.
Do not change permissions or enable collection automatically to complete this list.

| Check | Procedure / expected result | Status |
| --- | --- | --- |
| Fresh install and upgrade | Fresh and old acknowledgement/account/OS-permission installations remain manual until explicit automatic scope acceptance. Decline saves no automatic opt-in. | Unperformed |
| Input Monitoring | With the exact signed installed app, use the explicit setup action; verify system entry/relaunch behavior and capture across apps without Accessibility. Do not infer coverage from compilation. | Unperformed |
| Signal coverage and privacy | Test keyboard/delete/repeat/hold, clicks, scroll, stationary/moving/dragged pointer, app switching, multiple devices/displays and Secure Input. Inspect generated files for promised exclusions and gaps. No real private content. | Unperformed |
| Pause / all recording off / mode changes | Pause during capture, relaunch, restore OS access; it stays paused until Resume/Start. Disable automatic during work; no late callback restarts it. Disable all recording; both paths stop. | Unperformed |
| Idle and return | After five continuous idle minutes, capture stops. The public OS idle counter detects renewed activity without another logger. Resume starts Unknown; no bins fill paused time. | Unperformed |
| Actual lock / unlock | Lock during normal activity and during a break. Capture stops immediately. Unlock resumes only when consent/pause permits; intention does not silently carry through a lifecycle pause. | Unperformed |
| Actual sleep / wake | Test lid/display/system sleep and overlapping lock/sleep notifications. No tap/writer duplication or fabricated sleep observations. | Unperformed |
| Login launch | Explicitly enable/deny/remove OS login item; inspect pending approval/off/enabled status. Login cannot bypass recording consent/pause. Closing window keeps menu app; Quit stops capture. | Unperformed |
| Midnight / clock / timezone | Cross local midnight and a timezone/clock change during declared work and a break. IDs/context/cooldown continue across file boundaries; elapsed intervals stay finite/nonoverlapping. | Unperformed |
| Notification actions | Allow/deny/quiet/Focus settings; exercise current/stale/duplicate Not working, Take, Skip, Snooze and break return, including rotation and pause/revoke. Requested is not assumed delivered/viewed. | Unperformed |
| Normal survey-free use | Manual/automatic Start, End, break and return have no survey prompt with checked-in configuration. Old saved survey switches do not reactivate it. | Unperformed |
| History / exports / edits | Empty/legacy/new/short auto files, long tags, valid/invalid/stale bounded correction, partial crash tails, corrupt metadata, deletion/Trash, single/all export and duplicate names. Compatible history stays available. | Unperformed |
| Progress / accounts | Mixed contexts and explicit breaks, correction decreases, midnight, offline restart, sign-out/second-account/sign-back. New work stays local; no pending record transfers accounts. | Unperformed |
| Crash / disk / resource use | Force quit using generated recordings, then recover only durable coverage. Test full/unwritable disk and repeated interruptions on disposable storage. Measure CPU, memory, handles, files and disk over 24–72h. No unbounded bin backfill. | Unperformed |
| Accessibility and windows | Full keyboard navigation/focus, VoiceOver spoken labels/order, Reduce Motion, light/dark, compact/expanded People, narrow supported display, scaling and long text. Component previews/source inspection are partial evidence only. | Unperformed |
| OS / hardware | Qualify advertised macOS 14+ versions and supported Intel/Apple Silicon hardware. Universal compilation is not runtime compatibility. | Unperformed |
| Signed delivery | Developer signing/provisioning, hardened runtime, notarization/Gatekeeper or Store export, exact-source package, GPL/store rights, final privacy/support URLs/screenshots. No submission without authorization. | Unperformed |
| Disposable-service compatibility | Two disposable accounts/project only: authenticated delivery, cumulative cap, server scope/version, race/withdrawal/receipt/deletion and correction decreases. Never enable participant collection for this check. | Unperformed |

Research stays disabled until reviewed approval/configuration and the separate service
qualification exist. Study prompts need their independent configuration/opt-in.
No clustering stability, fatigue accuracy or intervention benefit is established by
this checklist. Record results and failures against the exact build before release.
