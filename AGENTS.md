# Working on this Trio fork

Read `AI/README.md`, `AI/BASELINE.md`, and `AI/CHANGELOG.md` before changing this repository. These instructions record the owner's standing requirements.

## Real insulin delivery

This fork is used day to day with a real insulin pump and distributed through TestFlight. Treat changes as potentially affecting real insulin delivery, including changes presented as UI or usability work.

- Trace the affected path from user input or device data through validation, persistence, calculation, and pump commands. Identify whether a change can alter dosing, units, timing, rounding, settings, alarms, or confirmation/authentication.
- Preserve existing safety checks and fail-safe behavior. Do not assume one shared validator covers every dosing entry point.
- For behavior changes, reproduce the problem and add or update meaningful regression coverage. For insulin-related changes, cover relevant limits, missing/stale data, supported pump increments, duplicate commands, concurrency, and failure paths as applicable.
- Run the relevant tests and build checks when the required environment is available. State exactly what ran, what passed, and what remains unverified; code inspection and successful compilation are not proof of safe delivery.
- Testing is required for code changes. When Swift/Xcode cannot run locally, run the relevant GitHub Actions suites on the exact proposed commit and inspect their results before declaring the change verified. Skipped, queued, or build-only jobs do not count as passing tests. Report and resolve test failures; if infrastructure or permissions block execution, state that the change remains unverified.
- Use fixtures, mocks, simulation, or replay for verification. Do not use the owner's live pump as a test target.
- Keep the requested code work separate from distribution. Pulling, inspecting, or editing code does not authorize triggering a TestFlight release or changing signing credentials.

## Upstream compatibility

- `origin` is `aosire/Trio`; `upstream` is `nightscout/Trio`. The comparison branch is upstream `dev`.
- Before implementation, inspect the working tree, fetch the relevant refs, and record the actual baseline SHA. Preserve existing user changes.
- Use a focused `codex/` branch for each feature or fix. Keep patches small and follow existing architecture, naming, formatting, and localization conventions.
- Avoid unrelated refactors, formatting churn, dependency upgrades, submodule updates, and Xcode project edits.
- Preserve Git ancestry. Do not overwrite fork customizations or force-reset the fork to upstream to solve conflicts.
- Resolve conflicts by understanding both sides, rechecking safety assumptions, rerunning affected checks, and documenting the resolution. Future merges may need conflict resolution; do not promise conflict-free updates.
- Inspect the existing upstream-sync and TestFlight workflow before proposing changes to branch or release practices.

## Change history

- Record every AI-assisted repository change in `AI/CHANGELOG.md`, including documentation, build/workflow changes, and conflict resolutions.
- Each entry must identify the request, base/upstream SHA, affected files, behavior change, safety impact, verification results and limitations, upstream merge considerations, and reversal approach. Add commit/PR references when they exist.
- Keep `AI/BASELINE.md` as the original onboarding snapshot. Record subsequent upstream syncs as new change-log entries with old/new SHAs.
- Update `AI/REPO_MAP.md` when relevant architecture or verification procedures change.
- Never put credentials, signing material, personal glucose/pump exports, or other private therapy data in this public repository or its change log.
