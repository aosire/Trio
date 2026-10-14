# Assessment of five requested improvements

Historical assessment. Implementation records and subsequent verification are in `CHANGELOG.md` and the feature-specific documents; the statements below describe the inspection before implementation.

Date: 2026-10-14. Inspected commit: `318e0d6929e7aa760c0863fe373161d760f141b4`; application and driver sources remain at the initial upstream `dev` baseline `1bacd86fb19dc325dff044b8cfe52fb7da6c8b98`. This document proposes implementation and verification work. No application changes or new feature tests have been made or run.

## Proposed sequence

| Work | Relative scope | Main reason for sequencing |
| --- | --- | --- |
| Reliable bolus cancellation | Medium–large, safety-critical | Investigate the reported loss of cancellation intent first |
| Fixed glucose chart bounds | Small–medium | Contained display change with a concrete reproducible outlier case |
| 15-minute predicted glucose | Small–medium | Existing forecast infrastructure; prediction semantics need care |
| Exercise preset and Watch trigger | Small initial setup; medium for robust session tracking | Existing override and Shortcut mechanisms can be reused |
| Cronometer import | Feasibility probe, then medium–large | External sample fidelity, deduplication, batch persistence and dosing interactions |

Scope labels compare engineering work; they are not delivery-time estimates. Keep each implementation in a focused branch/PR. The CI setup in PR #1 must be merged or carried into each implementation branch so fork tests actually execute.

## 1. Show predicted glucose in 15 minutes

### Existing pieces

- `Trio/Sources/Services/Alerts/ForecastedGlucoseEvaluator.swift` already accepts a horizon and samples IOB/COB/UAM/ZT predictions at five-minute intervals. It selects the minimum available curve for low-glucose alarm evaluation, not a universal best estimate.
- `Trio/Sources/Modules/Home/HomeStateModel+Setup/ForecastSetup.swift` loads forecast values and constructs the displayed min/max envelope.
- `Trio/Sources/Modules/Home/View/Chart/ChartElements/ForecastView.swift` anchors curve indices to the determination date, with each index representing 300 seconds.
- `Trio/Sources/Modules/Home/View/Header/CurrentGlucoseView.swift` is a likely location for a compact forecast label; Home state would supply a separate presentation value.

### Proposed change

Add a display selector that consumes an immutable, timestamped forecast snapshot. Show either a clearly labelled conservative forecast or a range across the existing scenarios; the graph's envelope is not a statistical confidence interval. Do not silently average the curves or describe the alarm evaluator's minimum as a central prediction.

Define the target as now plus 15 minutes. Index 3 represents 15 minutes after a fresh forecast's origin; it is not always 15 minutes from now once the determination ages. Select/interpolate using actual timestamps, and show the forecast's age. Missing, too-short, invalid or stale data should produce an unavailable/stale display rather than reuse an old number. Keep the existing dosing decision and alarm thresholds unchanged.

### Required verification

- Fresh and aged snapshots; exact boundaries and interpolation between five-minute samples; timestamps around timezone/DST changes; out-of-order updates.
- Missing curves, short arrays, missing determination dates and invalid input.
- mg/dL and mmol/L conversion/rounding, accessibility labels and compact display layouts.
- Tests that display selection does not mutate the determination or change dosing output. Extend `TrioTests/ForecastedGlucoseEvaluatorTests.swift` only where behavior is shared; otherwise use a focused display-selector suite.
- Decide separately whether the first version includes Watch/Live Activity; adding their labels requires their own snapshot serialization and stale-data tests.

## 2. Exercise logging and Apple Watch automation

### Existing pieces and integration route

`Trio/Sources/Models/Override.swift` already represents percentage, optional target and SMB-off settings. `Trio/Sources/Services/Adjustments/AdjustmentManager.swift` is the shared writer for override/temp-target activation and cancellation. Existing activation ends other active adjustments, so ownership and user changes matter.

`Trio/Sources/Shortcuts/Override/ApplyOverridePresetIntent.swift` exposes "Activate an override" and supports an explicit confirmation choice. `OverridePresetsIntentRequest.swift` invokes the adjustment manager. Apple documents personal-automation triggers for selected Watch workout types at start/end, and supports running Watch workout automations automatically. Therefore the first integration to validate is Watch Workout -> personal automation -> Trio preset, using the existing intent. Check the workout-type options on the target iOS version, including whether indoor walking can be distinguished as requested. [Apple workout triggers](https://support.apple.com/en-au/guide/shortcuts/apd932ff833f/ios), [automatic personal automations](https://support.apple.com/en-euro/guide/shortcuts/-apd602971e63/ios).

### Proposed change

Start with a named, user-configured exercise preset, a prominent active-mode indicator, a bounded duration, and an activity history entry. Reuse the existing override/target machinery and show exactly which settings the preset changes. Do not invent carbs, subtract actual carbs, modify IOB, or derive dosing amounts from calories burned. An override percentage is not necessarily a strict percentage cap on all insulin delivered; verify the actual algorithm effects.

For a robust second step, add a small exercise-session coordinator and session-aware intents. Record a run identifier, start/end and expiry, the adjustment activated for that session, and its origin. Duplicate starts must not repeatedly restart or extend a mode. An end event may only end the same exercise-owned adjustment; it must not cancel a newer manual override. Define pause/resume and optional post-workout behavior explicitly. Missed or delayed events, manual termination and restart recovery need visible, bounded behavior. Do not replay old workout history as a new dosing instruction.

Native HealthKit history import can supply exercise records, but do not assume it supplies immediate start/stop notifications from Apple's Workout app. Apple's mirroring example is for an app's own Watch session and companion app; it is not evidence of access to another app's active session. Starting a second Watch workout session can end the first. The Shortcut route avoids requiring Trio to own the workout. [Apple mirroring example](https://developer.apple.com/videos/play/wwdc2023/10023/), [single-session constraint](https://developer.apple.com/documentation/healthkit/hkerror/code/erroranotherworkoutsessionstarted?language=objc).

### Required verification

- Deterministic session/clock tests: duplicate, delayed and reordered start/end, expiry, restart, manual replacement, lost end event, and overlapping event sources.
- Extend `TrioTests/AdjustmentsTests/AdjustmentManagerTests.swift` for activation/ownership and cancellation behavior.
- Replay representative recorded/synthetic algorithm inputs with the preset: falling/rising glucose, meal COB, high IOB, low-glucose conditions, SMB on/off and dosing-mode clamps. Check intended effects, existing limits, and return from the mode. Configure no clinical percentages or targets by default during this assessment.
- Verify actual Watch/phone automation, locked-phone/background execution, permissions and connectivity on devices, initially in a mode that records events without altering therapy. GitHub simulator tests alone cannot establish real Watch event delivery reliability.

## 3. Import Cronometer foods in a reviewable batch

### Feasibility and existing pieces

Cronometer documents an Apple Health integration with read/write category permissions, and its timestamp feature is documented for Gold users. These pages do not establish exactly which per-food identifiers, nutrient values, grouping, names or times reach HealthKit in the current app. No current supported personal-account API was verified. Treat HealthKit as the first route to investigate, rather than committing to an undocumented login/scraping integration. [Cronometer integration](https://support.cronometer.com/hc/en-us/articles/360020734212-Apple-Health-Apple-Watch), [timestamps](https://support.cronometer.com/hc/en-us/articles/360021811032-Timestamps).

`Trio/Sources/Services/HealthKit/HealthKitManager.swift` currently requests `read: nil` and exports carbs, protein and fat, among other data. Import requires separate read permissions and a source-filtered query layer. HealthKit exposes source identity and sample UUIDs; anchored queries report additions and deletions. [HealthKit source identity](https://developer.apple.com/documentation/healthkit/hkobject/sourcerevision), [anchored queries](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery).

`CarbsEntry` already contains carbs, protein, fat and time fields. However, `saveCarbsToCoreData` and `saveCarbEquivalents` in `Trio/Sources/APS/Storage/CarbsStorage.swift` use `entries.last`; they are not a general multi-food batch persistence API. The existing remote filter also deduplicates by date, and persisted entries receive new local UUIDs. Reusing this path without additional identity/accounting would lose or duplicate food records. Fat/protein conversion can generate delayed carb-equivalent entries and must not run twice.

### Proposed change

First build a read-only sample inspection/preview with synthetic fixtures and an optional on-device diagnostic. Verify macro quantities/units, total-vs-net-carbohydrate meaning, genuine meal timestamps, same-time foods, identifiers and edit/delete behavior. Confirm whether HealthKit preserves food names or only nutrient totals. If exports are daily totals, have unusable timestamps, or cannot support reliable grouping, keep those records out of dosing and require manual time/group review or assess an explicit file-import alternative.

Then implement an import inbox: open Trio -> see new source-labelled meals -> review times and carbs/protein/fat -> one action records the selected batch -> open the existing bolus calculator if requested. Retain its existing dose review/authentication. Opening the app or receiving data must not itself issue a bolus.

Store durable external-source identities and the import decision independently from transient query anchors. Exclude Trio's own HealthKit writes to prevent feedback loops. Handle additions, edits, removals and deletion/recreation without treating them as extra meals. Imported meals must not be re-exported into a loop. Meals already manually recorded or already covered by a bolus need explicit reconciliation. Distinct meal times must remain distinct; one global total at the current time is unsuitable for an arbitrary batch.

Use an atomic, error-propagating batch-import operation, or group samples into a correctly persisted single meal where appropriate. Persist all selected meals and import identifiers before triggering recalculation, and recover safely from interruption. Apply the intended fat/protein policy once per meal. The inspected storage helpers enter conversion based on populated fat/protein values and do not themselves check `useFPUconversion`; importing those macros must not accidentally enable conversion by bypassing UI assumptions. Distinguish recording nutrient facts from enabling their dose-affecting conversion. Changes to a previously bolused meal cannot undo insulin already delivered; show the discrepancy without silently issuing a compensating dose.

### Required verification

- Sample fixtures: multiple foods with the same timestamp, meals with different timestamps, mixed/late-arriving macro samples, missing macros, future or midnight-only times, total/net carb ambiguity, unit conversion and source filtering.
- Exactly-once behavior across repeated app opens, edits, deletion/recreation, reinstalls/query-anchor resets and interrupted import commits. Avoid using timestamps as the only identity.
- Core Data migration and atomic rollback, all-entry persistence, FPU creation exactly once, HealthKit/Nightscout/Tidepool feedback prevention.
- Backdated food and previously delivered insulin tests. The existing disabled `testHandleBolusCalculationFunction` does not provide this coverage; add deterministic regressions or repair the relevant test before relying on the feature.
- Denied/revoked read access, partial data and delayed sync must produce an honest preview state. Test actual Cronometer -> HealthKit -> Trio preview on a device before connecting import to dosing.

## 4. Fixed chart minimum and maximum

### Existing pieces and proposed change

`Trio/Sources/Modules/Home/HomeStateModel+Setup/ChartAxisSetup.swift` derives bounds from measured glucose and forecasts and chooses stepped upper limits. The reported outlier behavior is consistent with this auto-scaling path; the particular reading has not been reproduced.

Add Auto/Fixed chart scaling and persisted minimum/maximum in `TrioSettings`, with controls in the existing chart/display settings. Persist bounds in one canonical unit and convert for display. Existing installations retain Auto by default. Validate ordered bounds and reject invalid inputs; round-trip settings exports and migrations.

Apply a fixed display domain in `MainChartView.swift` and its glucose/forecast elements. Do not replace off-scale readings with the boundary value: that creates false flat lines. Hide off-scale marks and handle discontinuities/clipping so forecasts or other annotations do not misrepresent hidden values. Current-glucose text, alarms, history and algorithm inputs must continue to use complete data. Do not delete or filter an outlier from the underlying glucose store as part of a chart preference.

Define initial scope as the main glucose chart; Watch, Live Activity and treatment-preview charts currently calculate their bounds separately and would need explicit additional changes to share this preference.

### Required verification

- A large single-reading outlier and forecasts beyond the range do not change fixed bounds; valid ordinary readings retain useful scale.
- Out-of-range low and high points, chart gaps, forecast cones, target/threshold rules and carb/insulin annotations; crossing the plot edge must not create false boundary values.
- Auto/Fixed switching, cold launch, older settings files, settings import/export, mmol/L/mg/dL switching, and invalid min/max.
- Screenshots/render review on representative phone sizes and accessibility text sizes. Assert algorithm input/output data remains unchanged by display settings.

## 5. One-press, reliable bolus cancellation

### Observed code and limits of the finding

In `Trio/Sources/APS/APSManager.swift:705`, cancellation returns silently unless cached pump status currently says bolusing. Home and Treatments launch a task per tap and discard the completion callback. After a cancellation error, `APSManager` still calls `clearBolusReporter()`, which removes the progress observer and clears the progress value. There is no app-level persistent cancellation-intent coordinator in these paths. These are plausible contributors to the reported behavior, not a reproduced diagnosis.

The relevant pinned Omnipod driver is `OmnipodKit/OmnipodKit/PumpManager/OmniPumpManager.swift:2756`. It already creates a Cancel Bolus session, checks pod/setup state, and handles uncertain delivery. `PodCommsSession.cancelDelivery` attempts to resolve a previous unacknowledged command before sending another and tracks the pending stop command. Omnipod 5 shares the universal driver path. App-level retries must cooperate with this existing protocol logic.

### Proposed change

Create one serialized cancellation coordinator shared by Home, Treatments and Watch. A tap records an intent associated with the current pod and original bolus, exposes Requested/Waiting for connection/Cancelling/Confirmed/Unable to confirm states, and starts the operation immediately where possible. Additional taps must not create competing commands. Keep the request pending through transient cached-state races and bounded communication retries, with status reconciliation through the driver.

The public pump API cancels the current bolus rather than accepting an arbitrary historical dose ID. Therefore stale intent must not survive into a different bolus or replacement pod and cancel it. Define identity checks, expiry, restart recovery and behavior for new manual/automatic boluses while cancellation is unresolved. A pending cancel must never silently resume a dose. Do not call a missing connection or a locally cleared progress indicator a confirmed stop.

On acknowledgement, reconcile delivered insulin and pump history before downstream IOB/calculator refresh. If the original bolus naturally finished, report that outcome distinctly. On failure or uncertain acknowledgement, preserve the relevant progress/uncertainty and surface the failed stop; do not clear the UI into an apparent success. Insulin can continue while a radio command is pending, and already delivered insulin cannot be reversed by this feature.

Prefer an app-layer fix preserving the submodule pin. If a driver change proves necessary, isolate it in the driver repository with its own tests and record both SHAs; do not hide edits inside an otherwise unchanged pinned submodule.

### Required verification

- Deterministic mocked-pump tests: tap during initiation, stale false bolusing state, repeated taps, busy transport, disconnect/reconnect, timeout, lost acknowledgement, failure then success and exactly one visible final result.
- Bolus completes while cancellation is queued; new bolus starts; pod replacement; restart/background transitions; old callbacks arrive after a new session. A stale cancel must never affect a later dose.
- Cancellation of manual and SMB-originated delivery where supported; confirmed partial delivery updates pump history/IOB without adding or losing insulin records.
- Home/Treatments/Watch UI consistency, accessibility, pending/failure visibility and retention of progress reporting until appropriate resolution.
- Omnipod driver-level tests/replay for pending-command resolution and stop acknowledgement. CI mocks do not prove radio reliability. Any required hardware verification belongs on a non-therapy test device/bench, not the active therapy pod.

## Shared acceptance and release approach

For each implementation: reproduce or define the expected behavior with fixtures; add focused regressions; run the relevant algorithm package and full iOS suites on GitHub Actions; inspect logs for skipped cases and actual test execution; record the exact commit, results, limits and upstream merge considerations in `AI/CHANGELOG.md`. Broader green tests cannot substitute for the new feature-specific regressions.

Use physical-device checks for real HealthKit permissions/exports, Apple Watch automation/background delivery, and UI behavior that a simulator cannot establish. Keep initial external-data probes and exercise event logging separate from therapy changes. No changes should be tested by issuing experimental commands to an active therapy pump. TestFlight distribution is a separate action after the changes and their evidence are reviewable.
