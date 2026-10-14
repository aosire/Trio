# AI-assisted change log

Record changes in chronological order. Include upstream syncs and conflict resolutions. The exact patch remains available through Git; entries here explain intent, safety impact, and verification.

## 2026-10-14 — Repository onboarding and standing rules

- **Request:** Pull the owner's fork, become familiar with it, treat real insulin use seriously, preserve upstream compatibility, and keep change records in `/AI`.
- **Base / upstream SHA:** `1bacd86fb19dc325dff044b8cfe52fb7da6c8b98` for both `aosire/Trio:dev` and `nightscout/Trio:dev` at fetch time.
- **Branch / commit / PR:** Originally prepared locally on `codex/repo-onboarding` without a commit or push; documentation is carried forward with the subsequent `codex/github-actions-tests` CI work.
- **Files:** Added root `AGENTS.md` and `AI/README.md`, `AI/BASELINE.md`, `AI/REPO_MAP.md`, `AI/CHANGELOG.md`.
- **Change:** Persisted the owner's working rules, recorded the initial Git/dependency baseline, mapped important code and verification paths, and created this log. Added local `origin` and `upstream` remotes and initialized the existing submodule pins.
- **Behavior / safety impact:** Documentation and local checkout setup only. No app, algorithm, pump driver, settings, CI, signing, or release behavior changed.
- **Verification:** Confirmed fork/upstream SHA and merge base match with 0/0 divergence and no tracked tree difference. Recursive submodule initialization succeeded; all 16 checked-out pins matched. Reviewed the new documentation, checked its repository links, and checked documentation whitespace. No Swift/Xcode tests or builds were run: neither tool is available on this Windows machine. AlgorithmPackage directory symlinks are materialized as text because local `core.symlinks=false`; recorded without changing tracked files.
- **Upstream considerations:** Changes are confined to new documentation files and the root instructions file. No existing upstream files or dependency pins were edited. Future conflicts involving these paths should preserve the owner's requirements and the accumulated change history.
- **Reversal:** Remove only these five newly added documentation files if the owner no longer wants them. No runtime rollback is needed. Local remote configuration and downloaded dependencies do not change the deployed app.
- **Distribution:** No workflow dispatch, TestFlight upload, live-pump test, or remote mutation.

## 2026-10-14 — Enable GitHub Actions tests for the fork

- **Request:** Tests must run somewhere even when the local machine cannot run Swift/Xcode.
- **Base / upstream SHA:** `1bacd86fb19dc325dff044b8cfe52fb7da6c8b98`, unchanged after refreshing both remotes.
- **Branch / commit / PR:** Published the workflow on `codex/github-actions-tests` at `bf3126e47f8fa279c29333b581b6dcbbaf7d2d49`; final tested head is `318e0d6929e7aa760c0863fe373161d760f141b4`, including these records and normalized workflow line endings. PR: https://github.com/aosire/Trio/pull/1, targeting the owner's fork `dev`, not upstream. The result-only updates to this log are local and uncommitted so the tested PR head remains unchanged.
- **Files:** `.github/workflows/unit_tests.yml`, `AGENTS.md`, `AI/REPO_MAP.md`, this log. Existing onboarding documents will accompany the change if publication succeeds.
- **Change:** Permit both existing test jobs on `aosire/Trio`; add manual dispatch and pushes to `codex/**`; include workflow YAML changes in triggers; set `TZ=Europe/Berlin` so package golden parity tests execute; restrict the workflow token to contents read. Keep the existing toolchain, simulator, tests, dependency pins, signing configuration, and TestFlight workflow.
- **Behavior / safety impact:** CI and engineering instructions only; no runtime/dosing changes. Future code changes require actual test results for the proposed commit; skipped jobs and successful compilation alone are insufficient.
- **Verification:** GitHub parsed and executed the updated workflow. `git diff --check` passed, the published tree matched local files, and the diff against the baseline contains only the workflow and five documentation files. The recent upstream run at https://github.com/nightscout/Trio/actions/runs/38059688928 also completed both jobs successfully on `d147fbe559ea64d675a929a8826ea175b3a7c6d7`.
- **Initial fork run:** https://github.com/aosire/Trio/actions/runs/38515849400 on `bf3126e47f8fa279c29333b581b6dcbbaf7d2d49`. The algorithm log reports 226 tests in 32 suites passing, including the golden parity suite with 14 cases. The iOS job started successfully. A subsequent workflow commit supersedes this run; inspect the latest commit's run for final verification.
- **Final fork results:** PR run https://github.com/aosire/Trio/actions/runs/38516065248 completed successfully on `318e0d6929e7aa760c0863fe373161d760f141b4`. Algorithm package: 226 tests in 32 suites passed, including all 14 golden parity cases. iOS simulator: 781 tests in 110 suites passed; the log confirms `TEST EXECUTE SUCCEEDED`. The push run https://github.com/aosire/Trio/actions/runs/38516033077 also completed both jobs successfully on the same head. The suites overlap; these counts are not additive counts of unique tests.
- **Existing exclusions:** The iOS log reports two upstream-disabled flaky tests: `BolusCalculatorTests.testHandleBolusCalculationFunction` ("Calculate insulin with backdated carbs") and `GlucoseStorageTests.testGlucoseAlarms` ("Test glucose alarms"). A separate backdated-carb calculation test remains enabled. The optional performance benchmark requires `TRIO_RUN_PERF=1` and was skipped. TandemKit's parameterized registry-emission test has no cases because its table is intentionally empty in the existing test source. No tests were newly disabled or expected outputs regenerated by this change. These existing coverage limits remain for future investigation.
- **Upstream considerations:** Small patch to the existing test workflow; retain upstream test/build steps on future syncs while preserving fork eligibility, triggers, read-only permissions, and parity timezone.
- **Reversal:** Revert the test-workflow patch and this entry's rule/map changes. No deployed app rollback is involved.
- **Distribution:** No TestFlight upload or release-workflow dispatch occurred. PR #1 was subsequently merged into `dev` at the owner's explicit request, producing `5f53f4f6865c7601e85eed13114f25d26dbe458c`; the test configuration is now part of the default branch.

## 2026-10-14 — Assess five usability and integration requests

- **Request:** Assess a 15-minute glucose prediction, exercise logging/Watch-triggered mode, Cronometer meal import, fixed glucose chart bounds and reliable one-press bolus cancellation, including implementation and testing needs.
- **Base / upstream SHA:** Inspected local head `318e0d6929e7aa760c0863fe373161d760f141b4`; application baseline remains `1bacd86fb19dc325dff044b8cfe52fb7da6c8b98`. No upstream sync performed for this assessment.
- **Branch / commit / PR:** Local `codex/feature-assessment`. New assessment and documentation edits are uncommitted; no new PR, remote mutation or changes to the tested CI PR head.
- **Files:** Added `AI/FEATURE_ASSESSMENT.md`; updated `AI/README.md` and this log. Preserved the prior uncommitted CI-result note.
- **Change / safety impact:** Documentation-only feasibility and test plan. Identified existing prediction/override/Shortcut infrastructure, a candidate cancellation-state/UI issue, and limitations in current HealthKit read access and multi-entry carb persistence. Findings describe inspected code, not a reproduced pump fault or completed feature.
- **Verification:** Read relevant app and pinned Omnipod driver code; checked current Apple/Cronometer primary documentation and recorded source links. Checked documentation whitespace and local links. No application changes, new test execution, hardware interaction or dosing/release actions.
- **Upstream considerations:** Keep implementations separate and focused. Prefer existing extension points and unchanged driver pins; document any necessary driver changes independently.
- **Reversal:** Remove the assessment and its README/log references; no runtime rollback is needed.

## 2026-10-14 — Merge CI setup and fix active-bolus cancellation

- **Request:** Merge existing PRs, then make a separate PR for an active, visibly progressing bolus whose Cancel button gives no immediate acknowledgement and may require repeated tapping.
- **Base / upstream SHA:** Fork `dev` after merging PR #1: `5f53f4f6865c7601e85eed13114f25d26dbe458c`; fetched upstream `dev`: `1bacd86fb19dc325dff044b8cfe52fb7da6c8b98`. Only PR #1 was open; its exact head had passed both test jobs before the authorized merge.
- **Branch / commit / PR:** `codex/reliable-bolus-cancel`; separate PR and CI results to be linked after publication. The new cancellation PR is not authorized to merge or release automatically by this request.
- **Files:** APSManager and new BolusCancellationCoordinator; DeviceDataManager/BolusStatus; Home/Treatments state and controls; shared status view in BolusProgressBar; dedicated English-source BolusCancellation string catalog; new BolusCancellationTests and Xcode source/resource registrations; this log and `AI/BOLUS_CANCELLATION.md`.
- **Behavior:** One press immediately shows a shared pending stop request. Duplicate presses join one operation. Preserve `.canceling` as active, keep progress on failure, perform bounded Omnipod retries for eligible communication errors, and show driver-confirmed success or explicit failure. A delayed acknowledgement shows an uncertainty warning without issuing an overlapping command.
- **Safety impact:** Stop commands only. Pending cancellation blocks new app-originated manual/SMB boluses; no basal/algorithm parameter change. Captured pump/pod/dose context prevents retries against a different bolus. No driver pin changes or experimental hardware commands. Requests are not replayed after an app restart.
- **Verification:** Added deterministic cancellation/identity/presentation regressions using fake driver operations and async gates. Git whitespace, string-catalog integrity and Xcode reference checks are performed locally; both GitHub suites and the new suite must be inspected before marking the PR ready. Current test status is given by the PR checks for its exact head, not earlier baseline results.
- **Limitations:** Real radio performance, phone layout/VoiceOver and background suspension behavior are not established by unit tests. A driver callback that never returns remains pending with a warning. Existing upstream disabled tests remain documented in the earlier CI entry.
- **Upstream considerations / reversal:** Focused app-layer patch; retain upstream algorithm and driver pins. Revert the feature commit to reverse the behavior; no migration. Preserve the earlier local assessment/README notes separately from the runtime PR.
- **Distribution:** Merged existing CI PR only. No cancellation-feature merge, TestFlight upload, signing change or live pump test.

## Entry template

For each subsequent change, record: date/title; request; fork base and upstream SHA; branch/commit/PR; files; before/after behavior; safety impact; tests/checks and exact results; unverified limitations; upstream merge/conflict considerations; reversal approach; and any explicitly requested distribution action and its result.
