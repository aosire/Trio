# Exercise sessions and optional preset application

Base: forecast PR #4 head `480e446c1586c418f9339e4a274e7b6454c48dec`, stacked after chart PR #3 and rooted in merged fork `2eb1a73354bc10667b5c26bffad170b5206bfd81`. Upstream remains `1bacd86fb19dc325dff044b8cfe52fb7da6c8b98`. Branch: `codex/exercise-mode`.

PR: https://github.com/aosire/Trio/pull/5. Initial CI head `b259a5a49fa662a5194c076cb5403791dd6f1d72` passed 226 algorithm tests including 14 golden cases, but failed the iOS build because this project defines a `Link` view modifier that shadows `SwiftUI.Link`. Qualifying the guide link fixes that name collision; full tests must run on the repaired head before readiness.

## User behavior

Home's Exercise button and Settings > Features > Exercise open the same configuration/history. Logging only is the default. Choose an existing override preset, a time limit (up to four hours), and explicitly enable preset application to use exercise mode. Save before starting. Changes affect future sessions, not an active session's expiry. The UI shows the selected preset's percentage, target and SMB-off flag and directs the user to review its full settings in Adjustments. No clinical percentage/target is chosen by this feature. An override percentage is not a hard cap on insulin.

An applied session uses a bounded, non-preset copy with its own identity, preserving the original preset's scalar therapy settings and leaving its duration/configuration untouched. The existing adjustment manager ends the prior active override, records history and refreshes the determination. Existing temp-target behavior is unchanged. No invented carbs, exercise-calorie model, IOB modification or new pump protocol is introduced. Applying the preset can change insulin decisions through the existing override machinery.

## Apple Watch route

Use an Apple Watch Workout start personal automation with Trio's **Start exercise session** action and the chosen activity. The intent defaults to confirmation when it would apply a preset; running without confirmation requires explicitly configuring that action and the automation. The user must configure personal automations on their phone; this patch cannot create them remotely. Apple documents workout type and start/end triggers: [Apple's guide](https://support.apple.com/en-gb/guide/shortcuts/apd932ff833f/ios). Available trigger types must be checked on the device; Walking may include outdoor walks. The selected activity label is not automatic indoor/outdoor classification.

Start returns a session UUID. An end automation must pass that exact UUID to **End exercise session**; it must not use the generic Cancel override action. A global variable overwritten by a newer workout is not reliable event-to-session matching. A start-only automation can use the bounded duration and manual end instead. The intent accepts an optional original start time and event UUID for workflows that preserve them. Starts older than two minutes or in the future are rejected. Duplicate identifiers remain consumed, and starts received while a session is open coalesce without extending it. This is not HealthKit workout-history replay, native live mirroring or pause/resume detection.

## Ownership, persistence and expiry

`ExerciseService` serializes foreground/intent mutations on the main actor. Its throwing atomic JSON journal records configuration, sessions and consumed-start aliases in the app's Documents `trio-exercise-sessions.json`. An ownership record is saved before any override activation. Failure to save it blocks activation. After-activation persistence failure retains the earlier preparing record for reconciliation. Corrupt/unreadable history blocks new therapy-changing starts. Recovery queries ownership and never replays activation. The journal is separate from the current settings export and is not uploaded by this feature; the applied override uses existing optional Nightscout history/upload behavior.

Owned override IDs use `trio-exercise:<session UUID>` plus the original start date. Conditional ending checks both within the existing adjustment serializer/transaction. A manual replacement or a later session cannot be cancelled by an old end receipt. Completed sessions never restore an earlier override automatically.

Manual preset/custom activation in Adjustments now uses that same writer to prevent races with workout starts. Home ending is conditional and serialized; automatic expiry captures the original row/expiry before starting its task. A stale cleanup cannot cancel a replacement, and a stale Home expiry cannot cancel a manually edited duration. Explicit editing detaches an exercise row's ownership marker, preserving that manual change from a later workout end. Each actually ended row is recorded once by the shared transaction.

Ordinary override expiry currently includes Home presentation handling. Exercise must not depend on that view running: `OpenAPS.fetchActiveOverrides` additionally excludes expired, future, malformed or indefinite **owned exercise** rows before constructing dosing inputs. Ordinary override semantics are preserved. Foreground reconciliation finalizes the corresponding row/history when possible. The dosing-input guard works independently of journal availability, a missed Watch end, Home visibility or background timer delivery.

## Verification and limits

Twenty fake-operation session tests cover default logging-only behavior, durable ownership before activation, duplicate/concurrent/stale events, manual replacement, old ends, expiry, restart, persistence failures, activation/cancellation failures, actual journal round-trip/corruption and dosing expiry boundaries. Nine Core Data integration tests cover copying all therapy fields, conditional ending/history, replacement, duplicate/missing preset atomicity, exact date ownership, the real OpenAPS fetch boundary, manual/exercise activation concurrency, stale edit cleanup and stale Home expiry. Existing algorithm/SMB/dosing-mode and app suites must also pass on the proposed head; no goldens are regenerated or tests disabled.

Unit tests do not establish Watch event fidelity, locked-phone execution, background suspension behavior, phone layout, larger text or VoiceOver. Validate actual automation initially with logging only. Physical protocol checks belong on non-therapy test hardware, never the owner's active pump. No TestFlight distribution is included.

## Upstream and reversal

Keep ownership checks inside the shared adjustment transaction and expiry filtering at the dosing-input boundary on future upstream merges. New preset attributes are copied as scalar values; review new fields and semantics when upstream changes the model. Driver/dependency pins remain unchanged and no Core Data schema migration is needed. End any active exercise session before reverting the feature, since rollback removes its dedicated expiry guard. Revert its commits to remove the UI/intents/service; the journal remains local history and is not replayed by older code.
