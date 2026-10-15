import SwiftUI
import UIKit

private struct FifteenMinuteForecastView: View {
    let snapshot: GlucoseForecastSnapshot?
    let timerDate: Date
    let glucoseDate: Date?
    let units: GlucoseUnits
    @State private var showExplanation = false

    private func ageText(now: Date) -> String? {
        guard let snapshot, now >= snapshot.origin,
              now.timeIntervalSince(snapshot.origin).isFinite,
              now.timeIntervalSince(snapshot.origin) < 24 * 60 * 60
        else { return nil }
        let age = Int(now.timeIntervalSince(snapshot.origin) / 60)
        return String(localized: "Forecast \(age) min old", table: "GlucoseForecast")
    }

    var body: some View {
        let now = max(timerDate, Date())
        let estimate = snapshot?.estimate(now: now, glucoseDate: glucoseDate)
        let ageDescription = ageText(now: now)
        let value = (estimate?.formatted(units: units) ?? "—") + " " + units.rawValue
        let spokenValue = spokenDescription(estimate: estimate, age: ageDescription)
        return Button { showExplanation = true } label: {
            forecastLabel(value: value, age: ageDescription, available: estimate != nil)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Glucose forecast in 15 minutes", table: "GlucoseForecast")))
        .accessibilityValue(Text(spokenValue))
        .accessibilityHint(Text(String(localized: "Explains the forecast range", table: "GlucoseForecast")))
        .alert(String(localized: "About this forecast", table: "GlucoseForecast"), isPresented: $showExplanation) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "The displayed value or range samples the available IOB, COB, UAM and ZT scenarios at 15 minutes from now. It is not a confidence interval or a guarantee. Missing, invalid or stale forecasts and stale glucose show a dash. This display does not change dosing or alarms.", table: "GlucoseForecast"))
        }
    }

    private func spokenDescription(estimate: GlucoseForecastSnapshot.Estimate?, age: String?) -> String {
        let value: String
        if let estimate { value = estimate.formatted(units: units) + " " + units.spokenValue }
        else { value = String(localized: "Unavailable or stale", table: "GlucoseForecast") }
        return value + (age.map { ". " + $0 } ?? "")
    }

    private func forecastLabel(value: String, age: String?, available: Bool) -> some View {
        VStack(spacing: 2) {
            Text(String(localized: "In 15 min", table: "GlucoseForecast")).font(.caption2)
            Text(value)
                .font(.caption).fontWeight(.semibold).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
            if let age { Text(age).font(.system(size: 9)) }
        }
        .foregroundStyle(available ? Color.primary : Color.secondary)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - Device pickers

/// Presents the "Add CGM" / "Add Pump" pickers for the home screen.
///
/// Both selections are applied in `onDismiss` rather than inline: the home view already stacks several sheets,
/// and presenting the device setup sheet while the picker is still dismissing gets dropped by SwiftUI.
private struct DevicePickersModifier: ViewModifier {
    @Binding var showPumpSelection: Bool
    @Binding var showCGMSelection: Bool
    @Binding var pendingPump: PumpCatalogEntry?
    @Binding var pendingCGM: CGMCatalogEntry?
    let state: Home.StateModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showPumpSelection, onDismiss: {
                if let entry = pendingPump {
                    pendingPump = nil
                    state.addPump(entry)
                }
            }) {
                DevicePickerView(
                    title: String(localized: "Add Pump", comment: "The title of the pump chooser in settings"),
                    entries: DeviceCatalog.pumps
                ) { entry in
                    pendingPump = entry
                    showPumpSelection = false
                }
            }
            .sheet(isPresented: $showCGMSelection, onDismiss: {
                if let entry = pendingCGM {
                    pendingCGM = nil
                    state.addCGM(cgm: CGMModel(entry))
                }
            }) {
                DevicePickerView(
                    title: String(localized: "Add CGM", comment: "The title of the CGM chooser in settings"),
                    entries: DeviceCatalog.cgms
                ) { entry in
                    pendingCGM = entry
                    showCGMSelection = false
                }
            }
    }
}

extension View {
    func devicePickers(
        showPumpSelection: Binding<Bool>,
        showCGMSelection: Binding<Bool>,
        pendingPump: Binding<PumpCatalogEntry?>,
        pendingCGM: Binding<CGMCatalogEntry?>,
        state: Home.StateModel
    ) -> some View {
        modifier(DevicePickersModifier(
            showPumpSelection: showPumpSelection,
            showCGMSelection: showCGMSelection,
            pendingPump: pendingPump,
            pendingCGM: pendingCGM,
            state: state
        ))
    }
}

// MARK: - Zone B: header (pump panel / glucose bobble / loop status)

extension Home.RootView {
    var glucoseView: some View {
        CurrentGlucoseView(
            timerDate: state.timerDate,
            units: state.units,
            alarm: state.alarm,
            lowGlucose: state.lowGlucose,
            highGlucose: state.highGlucose,
            cgmAvailable: state.cgmAvailable,
            currentGlucoseTarget: state.currentGlucoseTarget,
            glucoseColorScheme: state.glucoseColorScheme,
            glucose: state.latestTwoGlucoseValues,
            cgmProgress: state.cgmProgressHighlight,
            cgmStatus: state.cgmDisplayState,
            cgmSensorExpiresAt: state.cgmSensorExpiresAt,
            cgmWarmupEndsAt: state.cgmWarmupEndsAt
        )
        .onTapGesture {
            if !state.cgmAvailable {
                showCGMSelection.toggle()
            } else {
                state.shouldDisplayCGMSetupSheet.toggle()
            }
        }
        .onLongPressGesture {
            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
            impactHeavy.impactOccurred()
            showSnoozeSheet = true
        }
        .accessibilityAction {
            if !state.cgmAvailable {
                showCGMSelection.toggle()
            } else {
                state.shouldDisplayCGMSetupSheet.toggle()
            }
        }
        .accessibilityAction(named: Text("Snooze alerts")) {
            showSnoozeSheet = true
        }
    }

    var pumpView: some View {
        PumpView(
            reservoir: state.reservoir,
            name: state.pumpName,
            expiresAtDate: state.pumpExpiresAtDate,
            activatedAtDate: state.pumpActivatedAtDate,
            timerDate: state.timerDate,
            pumpStatusHighlightMessage: state.pumpStatusHighlightMessage,
            battery: state.batteryFromPersistence
        )
        .onTapGesture {
            if state.pumpDisplayState == nil {
                // shows user confirmation dialog with pump model choices, then proceeds to setup
                showPumpSelection.toggle()
            } else {
                // sends user to pump settings
                state.shouldDisplayPumpSetupSheet.toggle()
            }
        }
        // group reservoir/battery/pod into one button so VO reads it as a single control
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(
            state.pumpDisplayState == nil
                ? String(localized: "Opens pump setup", comment: "Accessibility hint")
                : String(localized: "Opens pump settings", comment: "Accessibility hint")
        ))
        .accessibilityAction {
            if state.pumpDisplayState == nil {
                showPumpSelection.toggle()
            } else {
                state.shouldDisplayPumpSetupSheet.toggle()
            }
        }
    }

    @ViewBuilder func rightHeaderPanel() -> some View {
        VStack(alignment: .center, spacing: 10) {
            /// Loop view at bottomLeading
            LoopView(
                dosingMode: state.dosingMode,
                timerDate: state.timerDate,
                isLooping: state.isLooping,
                lastLoopDate: state.lastLoopDate,
                manualTempBasal: state.manualTempBasal,
                lastGlucoseDate: state.lastGlucoseDate,
                lastPumpCommsDate: state.lastPumpCommsDate,
                hasDeviceIssue: state.hasDeviceIssue,
                determination: state.determinationsFromPersistence
            )
            .onTapGesture {
                state.isLoopStatusPresented = true
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text(String(localized: "Opens loop status", comment: "Accessibility hint")))
            .accessibilityAction { state.isLoopStatusPresented = true }
            /// eventualBG string at bottomTrailing

            if let eventualBG = state.enactedAndNonEnactedDeterminations.first?.eventualBG {
                let eventualGlucose = eventualBG as Decimal
                HStack {
                    Image(systemName: "arrow.right.circle")
                        .font(.callout)
                        .fontWeight(.bold)

                    Text(state.units == .mgdL ? eventualGlucose.description : eventualGlucose.formattedAsMmolL)
                        .font(.callout)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Eventual glucose"))
                .accessibilityValue(Text(
                    (state.units == .mgdL ? eventualGlucose.description : eventualGlucose.formattedAsMmolL)
                        + " " + state.units.spokenValue
                ))
            } else {
                HStack {
                    Image(systemName: "arrow.right.circle")
                        .font(.callout).fontWeight(.bold)
                    Text("--")
                        .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Eventual glucose"))
                .accessibilityValue(Text(verbatim: "--"))
            }
            FifteenMinuteForecastView(
                snapshot: state.glucoseForecastSnapshot?.origin == state.enactedAndNonEnactedDeterminations.first?.deliverAt
                    ? state.glucoseForecastSnapshot : nil,
                timerDate: state.timerDate,
                glucoseDate: state.cgmAvailable ? state.latestTwoGlucoseValues.last?.date : nil,
                units: state.units
            )
        }
    }
}
