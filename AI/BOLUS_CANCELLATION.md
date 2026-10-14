# One-tap cancellation of an active bolus

Date: 2026-10-14. Fork base: `5f53f4f6865c7601e85eed13114f25d26dbe458c` (CI PR #1 merged). Upstream application baseline: `1bacd86fb19dc325dff044b8cfe52fb7da6c8b98`. Branch: `codex/reliable-bolus-cancel`.

## Requirement

While an active bolus shows increasing delivery progress, one press of Cancel must immediately acknowledge the request. It must not require repeated tapping to start competing stop commands. Pending and failed stops must remain visible until the driver confirms a stop or the user explicitly retries after failure. Never present a requested stop as a confirmed stop.

## Findings

- `BaseAPSManager.cancelBolus` previously returned without any result when cached status did not say bolusing.
- It cleared the progress reporter even after the driver reported a cancellation failure.
- `BaseDeviceDataManager` mapped the driver's `.canceling` state to `.noBolus`. The Omnipod driver publishes `.canceling` while its stop command is unresolved; Trio could therefore remove progress while the radio operation was still underway.
- Home and Treatments discarded the cancellation callback and exposed no shared pending state. Each tap started a separate task.

These code findings explain plausible failure/feedback paths. The original device incident has not been replayed and there is no claim that every communication failure is caused by these paths.

## Implementation

- `BolusCancellationCoordinator` synchronously publishes a pending state and reserves one task before notifying subscribers. Repeated taps, including a reentrant publisher subscriber, join the reserved task.
- Home and Treatments immediately copy that state on the main actor. They share a status panel with progress, a spinner, clear waiting/uncertain wording, an explicit failure retry, and a pump-confirmed result. The panel remains visible independently of the progress reporter.
- Both Cancel icons and the result-panel actions have a minimum 44-by-44-point tap area. VoiceOver retains the estimated-delivery value alongside the pending/result description. A terminal failure warning can be explicitly dismissed without sending a pump command; dismissal does not stop insulin and does not release a still-pending command.
- `.canceling` maps to an active bolus presentation state; it no longer means no bolus.
- The pump receives an explicit stop even when a cached `.noBolus` flag would previously have dropped the request. Missing pumps and changed contexts report a failure instead of returning silently.
- Omnipod communication/connection failures permit at most three attempts, with 0.5 seconds between completed attempts, only when the original dose has an identifiable start date. Omnipod's existing driver resolves pending/unacknowledged stop commands. Other drivers get one attempt; configuration, device-state and generic uncertain-delivery errors do not opt into automatic retries.
- Before sending and after acknowledgement, validate the captured manager identity, pod activation date and dose start. Revalidate after retry waits. Never apply an old retry to a newer in-progress/initiating bolus or changed pump/pod. Unknown dose identity disables delayed retries.
- The visible Retry action reuses the failed request's captured context. Dismissing a result or beginning a new bolus clears that saved retry; a stale Retry control cannot capture a later bolus as a new target.
- After 10 seconds without resolution, show/alert "Bolus stop not confirmed" while keeping the request reserved. A watchdog cannot create a second command or pretend to cancel a hanging driver callback.
- While a cancellation is pending, block new app-originated manual bolus and SMB commands. Basal delivery and the dosing algorithm are not changed. The pending restriction ends when the operation resolves; a new bolus request clears an old terminal presentation result.
- Only driver-confirmed success clears the reporter and requests a fresh standalone determination. Failure preserves delivery reporting and surfaces an alert. The driver remains responsible for recording the actual partial dose.

## Verification

`TrioTests/BolusCancellationTests.swift` covers synchronous acknowledgement, duplicate/reentrant taps, bounded automatic retries, terminal failure and explicit retry, rejected errors, delayed/lost acknowledgement without overlapping commands, stale watchdogs, changed context before/during/after commands, pump/pod/dose identity, stale cached flags, and the `.canceling` presentation mapping.

The test doubles inject driver responses and synchronization gates; they do not connect to hardware and do not rely on real-time sleeps. The existing full algorithm and iOS suites must also pass on the proposed commit. CI links and observed results are recorded in the PR and `AI/CHANGELOG.md`; no earlier baseline run verifies this change.

English source strings use the separate `BolusCancellation.xcstrings` table alongside the existing main catalog. The Xcode project changes only register that resource, the coordinator and regression-test files. Pump submodule pins, algorithm code, signing and TestFlight workflows stay unchanged.

## Limits and follow-up checks

- A request is not an instantaneous physical stop. Insulin can continue until the pod receives/processes the command; already delivered insulin cannot be reversed.
- A driver callback that never resolves keeps the cancellation pending and new boluses blocked for this process. The warning is visible; the app does not time out the callback and start overlapping radio commands.
- Requests are not persisted/replayed across app restarts. This avoids replaying a historical stop against another bolus. Existing driver pending-command persistence/reconciliation is unchanged.
- GitHub tests cannot prove radio reliability or visual layout on the actual phone. Review Home/Treatments layout, VoiceOver and larger text on a simulator/device. Any physical protocol validation must use a non-therapy test device/bench; the active therapy pod is not a test target.
- If hardware evidence shows a separate driver defect, address it independently with driver tests and an explicitly recorded submodule revision. This patch does not modify OmnipodKit.

## Upstream merge and reversal

The patch uses app-level extension points and preserves the upstream ancestry. On future upstream changes to bolus state, progress reporting or pump cancellation, preserve the distinction between pending and confirmed stop and rerun these regressions. Revert this feature commit to restore previous app behavior; no data migration or driver rollback is required.
