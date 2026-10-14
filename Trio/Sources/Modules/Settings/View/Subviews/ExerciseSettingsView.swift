import CoreData
import SwiftUI
import Swinject

struct ExerciseSettingsView: View {
    private let resolver: Resolver
    @ObservedObject private var service: ExerciseService
    @State private var configuration = ExerciseConfiguration()
    @State private var activity: ExerciseActivity = .indoorWalk
    @State private var error: String?
    @FetchRequest(fetchRequest: OverrideStored.fetch(NSPredicate.allOverridePresets, ascending: true))
    private var presets: FetchedResults<OverrideStored>

    init(resolver: Resolver) {
        self.resolver = resolver
        service = resolver.resolve(ExerciseService.self)!
    }

    var body: some View {
        Form {
            configurationSection
            sessionSection
            automationSection
            historySection
            if let error = error ?? service.lastError { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(String(localized: "Exercise", table: "Exercise"))
        .onAppear { configuration = service.journal.configuration }
        .task {
            while !Task.isCancelled {
                await service.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
    }

    private var configurationSection: some View {
        Section {
            Toggle(String(localized: "Apply selected override when exercise starts", table: "Exercise"), isOn: $configuration.applyPreset)
            Picker(String(localized: "Exercise preset", table: "Exercise"), selection: $configuration.presetID) {
                Text(String(localized: "Select a preset", table: "Exercise")).tag("")
                ForEach(presets) { preset in
                    if let id = preset.id { Text(preset.name ?? id).tag(id) }
                }
            }
            Stepper(value: $configuration.durationMinutes, in: 5 ... 240, step: 5) {
                HStack {
                    Text(String(localized: "Time limit", table: "Exercise"))
                    Spacer()
                    Text(verbatim: "\(configuration.durationMinutes) min")
                }
            }
            if let preset = presets.first(where: { $0.id == configuration.presetID }) {
                presetSummary(preset)
            }
            Button(String(localized: "Save exercise settings", table: "Exercise")) {
                do { try service.configure(configuration); error = nil } catch { self.error = error.localizedDescription }
            }.disabled(service.busy || !configuration.isValid)
        } footer: {
            Text(String(localized: "Logging only is the default. Enabling the preset replaces the running override using a bounded copy of your selection. Changes apply to future sessions. The original preset is unchanged. Review its settings in Adjustments; a percentage is not a hard cap on insulin delivered.", table: "Exercise"))
        }
    }

    private func presetSummary(_ preset: OverrideStored) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(localized: "Percentage", table: "Exercise"))
                Spacer()
                Text(verbatim: "\(preset.percentage)%")
            }
            HStack {
                Text(String(localized: "SMB disabled", table: "Exercise"))
                Spacer()
                Text(preset.smbIsOff ? String(localized: "Yes", table: "Exercise") : String(localized: "No", table: "Exercise"))
            }
            if let target = preset.target, target.decimalValue != 0 {
                let units = resolver.resolve(SettingsManager.self)!.settings.units
                HStack {
                    Text(String(localized: "Target", table: "Exercise"))
                    Spacer()
                    Text(verbatim: target.decimalValue.asUnit(units).description + " " + units.rawValue)
                }
            }
        }.font(.caption).foregroundStyle(.secondary)
    }

    private var sessionSection: some View {
        Section {
            if let session = service.activeSession {
                Text(activityName(session.activity)).fontWeight(.semibold)
                Text(session.appliesPreset ? String(localized: "Exercise override session", table: "Exercise") : String(localized: "Logging only", table: "Exercise"))
                Text(statusName(session.status)).font(.caption)
                Text(session.expiresAt, style: .relative)
                Button(String(localized: "End this exercise session", table: "Exercise")) {
                    Task {
                        do { try await service.end(sessionID: session.id); error = nil } catch { self.error = error.localizedDescription }
                    }
                }.disabled(service.busy)
            } else {
                Picker(String(localized: "Activity", table: "Exercise"), selection: $activity) {
                    ForEach(ExerciseActivity.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Button(String(localized: "Start exercise session", table: "Exercise")) {
                    Task {
                        do {
                            _ = try await service.start(activity: activity.rawValue, eventID: UUID(), observedAt: Date())
                            error = nil
                        } catch { self.error = error.localizedDescription }
                    }
                }.disabled(service.busy || configuration != service.journal.configuration)
            }
            if service.busy { ProgressView() }
        } header: { Text(String(localized: "Current session", table: "Exercise")) }
    }

    private var automationSection: some View {
        Section {
            Text(String(localized: "In Shortcuts, create an Apple Watch Workout start automation for Walking or Elliptical. Add Trio’s Start exercise session action and choose the matching activity. Walking may include outdoor walks; check the available trigger options. Save your configuration here first. To run without a prompt, explicitly disable Confirm before applying preset in that action and choose Run Immediately in the automation.", table: "Exercise"))
            Text(String(localized: "The time limit is the fallback if an end event is missed. For an end automation, save the identifier returned by Start and pass that exact identifier to End exercise session. Never use Cancel override as the workout-end action; it could stop a newer adjustment. Workout-type options and locked-phone delivery must be checked on your devices.", table: "Exercise"))
            Link(String(localized: "Apple’s workout automation guide", table: "Exercise"), destination: URL(string: "https://support.apple.com/en-gb/guide/shortcuts/apd932ff833f/ios")!)
        } header: { Text(String(localized: "Apple Watch Workout", table: "Exercise")) }
        .font(.footnote)
    }

    private var historySection: some View {
        Section {
            ForEach(service.journal.sessions.prefix(100)) { session in
                VStack(alignment: .leading, spacing: 3) {
                    Text(activityName(session.activity))
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                    Text(statusName(session.status)).font(.caption)
                    Text(session.appliesPreset ? String(localized: "Preset requested", table: "Exercise") : String(localized: "Logging only", table: "Exercise"))
                        .font(.caption2)
                }
            }
        } header: { Text(String(localized: "Recent exercise", table: "Exercise")) }
    }

    private func activityName(_ value: String) -> String { ExerciseActivity(rawValue: value)?.title ?? value }
    private func statusName(_ status: ExerciseSession.Status) -> String {
        switch status {
        case .preparing: return String(localized: "Awaiting reconciliation", table: "Exercise")
        case .active: return String(localized: "Active", table: "Exercise")
        case .ended: return String(localized: "Ended", table: "Exercise")
        case .expired: return String(localized: "Time limit reached", table: "Exercise")
        case .replaced: return String(localized: "Override replaced or no longer active", table: "Exercise")
        case .failed: return String(localized: "Preset activation failed", table: "Exercise")
        }
    }
}

struct ExerciseHomeButton: View {
    let resolver: Resolver
    let timerDate: Date
    @ObservedObject private var service: ExerciseService
    @State private var presented = false

    init(resolver: Resolver, timerDate: Date) {
        self.resolver = resolver
        self.timerDate = timerDate
        service = resolver.resolve(ExerciseService.self)!
    }

    var body: some View {
        Button { presented = true } label: {
            Label(String(localized: "Exercise", table: "Exercise"), systemImage: "figure.walk")
                .font(.caption)
                .foregroundStyle(service.activeSession == nil ? Color.secondary : Color.orange)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(service.activeSession == nil ? String(localized: "No active session", table: "Exercise") : String(localized: "Exercise session active", table: "Exercise")))
        .sheet(isPresented: $presented) {
            NavigationStack {
                ExerciseSettingsView(resolver: resolver)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Done")) { presented = false } } }
            }
        }
        .task(id: timerDate) { await service.refresh() }
    }
}
