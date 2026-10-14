# Repository map

Inspected at baseline `1bacd86fb19dc325dff044b8cfe52fb7da6c8b98` on 2026-10-14. Recheck the implementation after upstream updates. This map identifies review entry points; it does not certify the code's safety.

## App and UI

- `Trio.xcworkspace` / `Trio.xcodeproj`: iOS app, tests, watch targets, and extensions. CI uses the workspace.
- `Trio/Sources/Application/TrioApp.swift`: SwiftUI entry point, persistent-store initialization and service startup; Swinject dependency assembler.
- `Trio/Sources/Application/AppDelegate.swift`: app lifecycle and notification integration.
- `Trio/Sources/Assemblies/`: APS, storage, service, UI, network, and security registrations.
- `Trio/Sources/Modules/`: feature modules commonly use `DataFlow`, `Provider`, `StateModel`, and `View` files. Home, Treatments, Settings, PumpConfig, and algorithm settings are useful starting points.
- `Trio/Sources/Modules/Treatments/TreatmentsStateModel.swift`: meal/bolus entry, calculator integration, max-bolus capping and authentication before delivery.
- `Trio/Sources/Modules/Home/HomeStateModel+QuickPickTreatments.swift`: quick-pick carb persistence and authenticated bolus enactment, with separate outcome reporting.
- `Trio/Sources/Localizations/Main/Localizable.xcstrings`: main string catalog. Follow `CONTRIBUTING.md`: English source strings; existing localization mechanisms.
- `LiveActivity/`, `Trio Watch App/`, related watch extensions, and `Trio/Sources/Services/WatchManager/`: additional displays and watch interactions. Some watch actions can initiate treatment, so they are not purely presentational.

## Data to pump commands

1. `Trio/Sources/APS/FetchGlucoseManager.swift` and `APS/CGM/` ingest readings, including calibration/smoothing and CGM integration.
2. `Trio/Sources/APS/DeviceDataManager.swift` integrates pump managers, heartbeat/update coordination, events, status, and device alerts. `APS/PluginManager.swift` and `APS/Devices/DeviceCatalog.swift` describe supported plugins/devices.
3. `Trio/Sources/APS/Storage/` and `Model/` persist glucose, carbs, pump events, determinations, overrides, and other state. `Model/CoreDataStack.swift` and initialization coordination matter for concurrency and migrations. JSON/file storage also remains in use.
4. `Trio/Sources/APS/APSManager.swift` coordinates the loop, glucose validation, profile/autosensitivity preparation, determination, and pump enactment. Its actor guard coordinates loop and standalone determinations.
5. `Trio/Sources/APS/OpenAPS/OpenAPS.swift` adapts stored data into native algorithm models, calculates meal/IOB/autosensitivity/determination, and saves results. The inspected implementation calls the Swift generators; older port-roadmap prose is not a reliable description of the current runtime.
6. `Trio/Sources/APS/OpenAPSSwift/` implements profile generation, IOB, meal/COB, autosensitivity, forecasts, dynamic ISF, basal determination, SMB decisions, and pump-rate rounding.
7. `APSManager` enacts temp basal and SMB commands using the selected LoopKit `PumpManager`. Device-specific protocol behavior is in the pinned driver submodules.

## Safety-sensitive review points

- `APSManager`: data freshness/count checks, pump state checks, manual-temp-basal handling, loop serialization, pump capability injection, rounding, and error reporting. A calculation can still run to update IOB/COB when glucose validation fails; follow the error and enactment flow, not just the calculation call.
- `Trio/Sources/APS/BolusCancellationCoordinator.swift`: app-level reservation for one active stop request, captured pump/pod/dose identity, bounded retries and delayed-confirmation warnings. `APSManager` connects it to the driver and blocks new boluses while pending. Home/Treatments share `BolusCancellationStatusView` in `Views/BolusProgressBar.swift`. See `AI/BOLUS_CANCELLATION.md` for behavior and verification limits.
- `Trio/Sources/Models/DosingMode.swift` and `Preferences+DosingMode.swift`: automation permissions and derived preference clamps. Recheck both profile creation and determination input preparation when changing mode behavior.
- `Trio/Sources/Services/BolusCalculator/BolusCalculationManager.swift`: manual bolus calculation and its settings/data inputs.
- `Trio/Sources/Services/BolusSafety/BolusSafetyValidator.swift`: max-bolus, IOB availability/max-IOB, and recent-bolus checks for external entry points such as Shortcuts and remote commands. This validator is not called centrally by every `APSManager.enactBolus` invocation.
- `Trio/Sources/Shortcuts/Bolus/`, `Services/RemoteControl/TrioRemoteControl+Bolus.swift`, `Services/WatchManager/AppleWatchManager.swift`, Treatments, and Home quick picks: trace each affected caller's own validation, authentication, units, command timing, and outcomes.
- `Trio/Sources/Services/Alerts/`: glucose/device alarms, not-looping monitoring, critical audio, acknowledgement, and cold-start replay. Display/notification fixes can affect warning delivery.
- Pump history and Core Data changes can affect IOB and later dose decisions. Settings or unit-conversion UI changes can alter algorithm inputs even when the dosing engine is untouched.

## Tests and build

- `GlucoseChartBounds` in `Models/TrioSettings.swift` and `HomeStateModel+Setup/ChartAxisSetup.swift`: validated display domain and original automatic scale. `UserInterfaceSettings` edits the canonical pair; Home chart elements clip only in fixed mode. `TrioTests/GlucoseChartBoundsTests.swift` covers outliers, units and persistence. See `AI/FIXED_GLUCOSE_CHART.md`.

- `TrioTests/OpenAPSSwiftTests/`: algorithm scenarios, limits, rounding, meal/IOB/autosensitivity, basal/SMB decisions, and parity fixtures.
- `TrioTests/`: bolus safety/calculator, dosing-mode clamps/migration, delivery-limit sync, pump history, Core Data, glucose smoothing, alerts, watch-adjacent features, and treatment tests.
- `TrioTests/BolusCancellationTests.swift`: deterministic fake-driver tests of cancellation acknowledgement, command coalescing, retries, watchdogs, stale status and pump/pod/dose identity. These tests do not establish physical radio reliability or phone layout/accessibility.
- `AlgorithmPackage/Package.swift`: standalone macOS algorithm package compiling the same sources through tracked symlinks. On macOS run `TZ=Europe/Berlin swift test --package-path AlgorithmPackage` so golden parity suites run rather than skip.
- `TrioTests/OpenAPSSwiftTests/Parity/ParityHarness.swift`: parity checks require `Europe/Berlin`; `Trio Tests.xcscheme` sets it. Keep golden recording off during verification. Do not regenerate expected outputs merely to make a changed algorithm pass.
- `.github/workflows/unit_tests.yml`: macOS 26 / Xcode 26.2, iPhone 17 iOS 26.2 simulator, `Trio Tests` scheme, pinned Swift package resolution, build-for-testing and test-without-building. The initial upstream workflow restricts both jobs to the `nightscout` owner. The local CI change allows `aosire/Trio`, adds manual dispatch and pushes to `codex/**`, stops ignoring workflow YAML changes, and pins `TZ=Europe/Berlin` for both suites. See the change log for publication and execution status; a local edit does not enable remote testing.
- Simulator test signing uses ad-hoc signing with app-group entitlements in that workflow. Copy the full relevant CI configuration when running tests; omitting entitlements can prevent the test host from starting.
- `BuildTools/`, `scripts/swiftformat.sh`, and existing build phases handle formatting. Avoid incidental edits across untouched files.

## TestFlight and upstream sync

- `.github/workflows/build_trio.yml` supports manual dispatch and a weekly schedule. It includes upstream synchronization of the branch of the same name, gated by token checks and `SCHEDULED_SYNC`, then building and TestFlight upload when its conditions are met.
- The build workflow selects Xcode 26.5 at this baseline, while the unit-test workflow selects 26.2. Inspect the relevant workflow before reproducing a build.
- `fastlane/Fastfile`: `build_trio` handles the app build/signing flow; `release` uploads `Trio.ipa` to TestFlight.
- `Config.xcconfig`, `BuildDetails.plist`, `.github/workflows/auto_version_dev.yml`, and `scripts/capture-build-details.sh` provide version/build identity. `ConfigOverride.xcconfig` is ignored for local signing overrides.
- Existing remote variables and credentials were not inspected. File contents describe potential workflow behavior, not proof of active account configuration.
- Before introducing fork customization, check that upstream-sync behavior preserves it and that the intended branch is buildable. Keep upstream updates, custom features, validation, and release actions understandable and separately recorded.
