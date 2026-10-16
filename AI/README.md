# AI work record

This folder records the owner's requirements and the differences introduced by AI-assisted work relative to upstream Trio `dev`.

## Standing requirements

1. Be thorough: this fork is used with a real insulin pump. A mistake can have practical consequences. Built-in safety features do not replace careful engineering and verification.
2. Keep future upstream `dev` merges practical. Use small, focused changes, preserve ancestry, and document conflict resolutions.
3. Keep a record here of every change so the owner can understand how the fork differs from base `dev`.

`../AGENTS.md` makes these requirements discoverable to future coding sessions.

## Documents

- [BASELINE.md](BASELINE.md): immutable onboarding commit, upstream comparison, dependencies, and environment limitations.
- [REPO_MAP.md](REPO_MAP.md): starting points for code navigation, safety review, and verification.
- [CHANGELOG.md](CHANGELOG.md): chronological record of AI-assisted changes and upstream syncs.
- [FEATURE_ASSESSMENT.md](FEATURE_ASSESSMENT.md): implementation options and required verification for the five requested improvements.
- [BOLUS_CANCELLATION.md](BOLUS_CANCELLATION.md): one-tap cancellation behavior and verification limits.
- [FIXED_GLUCOSE_CHART.md](FIXED_GLUCOSE_CHART.md): fixed Home chart bounds, scope and regression coverage.

## Comparing with upstream

Removed exercise logging/preset-session functionality is recorded historically in [EXERCISE_SESSIONS.md](EXERCISE_SESSIONS.md). Only compatibility expiry/ending for already-persisted overrides remains.

The removed Cronometer preview is recorded historically in [CRONOMETER_HEALTH_PREVIEW.md](CRONOMETER_HEALTH_PREVIEW.md); there is no active import/preview feature.

The fifteen-minute Home forecast is documented in [FIFTEEN_MINUTE_FORECAST.md](FIFTEEN_MINUTE_FORECAST.md).

Fetch first; do not merge simply to obtain a comparison:

```sh
git fetch origin
git fetch upstream dev
git rev-list --left-right --count upstream/dev...HEAD
git log --oneline upstream/dev..HEAD
git diff --stat upstream/dev...HEAD
git diff upstream/dev...HEAD
git diff HEAD
git status --short
```

The three-dot diff shows committed changes since the merge base. `git diff HEAD` also shows staged and unstaged tracked edits, while `git status` identifies untracked files. To inspect the complete current tracked tree against upstream, use `git diff upstream/dev`. The change log explains intent and validation; Git remains the source of truth for exact differences.

Initial onboarding created documentation locally without changing the remote repository or deployed app. The subsequent GitHub Actions work publishes these records together with the CI change on `codex/github-actions-tests`; see the change log for execution results. No release workflow or deployed app is changed by this documentation.
