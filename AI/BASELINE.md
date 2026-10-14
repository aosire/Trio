# Initial baseline — 2026-10-14

This is the original onboarding snapshot, not a rolling claim about current upstream state.

| Item | Recorded value |
| --- | --- |
| Fork | `https://github.com/aosire/Trio.git` |
| Fork branch | `dev` |
| Upstream | `https://github.com/nightscout/Trio.git` |
| Upstream comparison branch | `dev` |
| Fork and upstream commit | `1bacd86fb19dc325dff044b8cfe52fb7da6c8b98` |
| Commit subject | `CI: Bump APP_DEV_VERSION to 1.0.2.4 [skip ci]` |
| Recorded dev app version | `1.0.2.4` in `Config.xcconfig` |
| Commit divergence | 0 upstream-only / 0 fork-only commits |
| Tracked source difference | None before onboarding documentation |
| Local documentation branch | `codex/repo-onboarding` |

The workspace initially contained an empty Git repository. Fetched `origin`, checked out `dev` tracking `origin/dev`, initialized recursive submodules at their recorded commits, added `upstream`, and fetched upstream `dev` without merging. Then created the local documentation branch.

## Pinned submodules

All 16 submodules were initialized and verified against the superproject pins. No submodule revisions were changed.

| Path | Commit |
| --- | --- |
| AccuChekKit | `4f8c3a8cb50e68a979bdbed2e207aca00e4b35e0` |
| CGMBLEKit | `ea224e771fb3329a957a753296232c62a003a9fe` |
| DanaKit | `e157a861c691f44c84df6071233edb935c06e7dc` |
| EversenseKit | `e1bb6faf01bb4bd79872ae6d12787aea8bfe2ad5` |
| G7SensorKit | `dd91f465b8b7392354b74463b9b9cc7aae32db9f` |
| LibreLoop | `c6e9cc158b1922edb147a0ac3bd2ccc8e8541aa9` |
| LibreTransmitter | `41105123c3c4fb5c55ce89a38630cea2f8f7a17a` |
| LoopAlgorithm | `4604ee36f5acc3d00b2d07331a3a477570761374` |
| LoopKit | `f974241f5f25053d51da3e80833c85b13c387e6f` |
| MedtrumKit | `ef866fa68db22932271af9bce86372ced8604203` |
| MinimedKit | `a7b26858e3073ac8881e7303b675c6b0f8c51ee9` |
| OmnipodKit | `043b91dbf1958d26c55d927a6a8d651bc91f208d` |
| RileyLinkKit | `049f0d51b2fb90fa5180f3f62555d8c661b55968` |
| RoundWhiteDiscKit | `e66da6cc34680fecbbb87812279163dcc1a842b4` |
| TidepoolService | `99ac3544f8462973f6ea886d1a46c2954ad0cc0f` |
| dexcom-share-client-swift | `ff0d71433447af3c93dac450d95c14b63f58f417` |

Swift package pins are recorded in the existing workspace/project `Package.resolved` files and `BuildTools/Package.resolved`; Ruby dependencies are recorded in `Gemfile.lock`. They were not resolved, upgraded, or installed during onboarding.

## Verification and limits

- Initial tracked working tree was clean. Fork `HEAD`, upstream `dev`, and their merge base were the same SHA; tree comparison was empty.
- Recursive submodule initialization completed successfully; `git submodule status --recursive` showed every pin checked out without a mismatch marker.
- Environment: Windows PowerShell. Neither `swift` nor `xcodebuild` was available on PATH.
- Git has `core.symlinks=false` here. The two tracked links in `AlgorithmPackage` are checked out as text files containing their targets, not functioning directory symlinks. A macOS checkout should preserve those links for package testing. No tracked workaround was introduced.
- No app build, unit test, simulator run, algorithm replay, or physical-device test was performed. This is repository onboarding and an initial code map, not a complete safety audit.
- No remote push, workflow dispatch, TestFlight upload, signing change, or pump interaction occurred.
- The exact build installed on the owner's phone, pump model, CGM model, repository variables, and secret configuration were not established by this checkout.
