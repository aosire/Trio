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
- **Branch / commit / PR:** Published the workflow on `codex/github-actions-tests` at `bf3126e47f8fa279c29333b581b6dcbbaf7d2d49`. A follow-up commit includes these records and normalizes workflow line endings to preserve a small upstream diff. Final execution and PR references will be added when available.
- **Files:** `.github/workflows/unit_tests.yml`, `AGENTS.md`, `AI/REPO_MAP.md`, this log. Existing onboarding documents will accompany the change if publication succeeds.
- **Change:** Permit both existing test jobs on `aosire/Trio`; add manual dispatch and pushes to `codex/**`; include workflow YAML changes in triggers; set `TZ=Europe/Berlin` so package golden parity tests execute; restrict the workflow token to contents read. Keep the existing toolchain, simulator, tests, dependency pins, signing configuration, and TestFlight workflow.
- **Behavior / safety impact:** CI and engineering instructions only; no runtime/dosing changes. Future code changes require actual test results for the proposed commit; skipped jobs and successful compilation alone are insufficient.
- **Verification:** The recent upstream run at https://github.com/nightscout/Trio/actions/runs/38059688928 completed both algorithm tests and iOS simulator tests successfully on `d147fbe559ea64d675a929a8826ea175b3a7c6d7`. This establishes that the upstream CI configuration has run successfully, not that this fork's proposed commit has passed. Local YAML/static checks and fork execution results will be recorded below when available.
- **Initial fork run:** https://github.com/aosire/Trio/actions/runs/38515849400 on `bf3126e47f8fa279c29333b581b6dcbbaf7d2d49`. The algorithm log reports 226 tests in 32 suites passing, including the golden parity suite with 14 cases. The iOS job started successfully. A subsequent workflow commit supersedes this run; inspect the latest commit's run for final verification.
- **Upstream considerations:** Small patch to the existing test workflow; retain upstream test/build steps on future syncs while preserving fork eligibility, triggers, read-only permissions, and parity timezone.
- **Reversal:** Revert the test-workflow patch and this entry's rule/map changes. No deployed app rollback is involved.
- **Distribution:** No TestFlight upload or release-workflow dispatch is part of this change.

## Entry template

For each subsequent change, record: date/title; request; fork base and upstream SHA; branch/commit/PR; files; before/after behavior; safety impact; tests/checks and exact results; unverified limitations; upstream merge/conflict considerations; reversal approach; and any explicitly requested distribution action and its result.
