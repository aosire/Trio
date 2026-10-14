import AppIntents
import Foundation

enum ExerciseActivity: String, AppEnum, CaseIterable {
    case indoorWalk, elliptical, other
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Exercise activity", table: "Exercise"))
    static var caseDisplayRepresentations: [ExerciseActivity: DisplayRepresentation] = [
        .indoorWalk: DisplayRepresentation(title: LocalizedStringResource("Indoor walk", table: "Exercise")),
        .elliptical: DisplayRepresentation(title: LocalizedStringResource("Elliptical", table: "Exercise")),
        .other: DisplayRepresentation(title: LocalizedStringResource("Other exercise", table: "Exercise"))
    ]
    var title: String {
        switch self {
        case .indoorWalk: return String(localized: "Indoor walk", table: "Exercise")
        case .elliptical: return String(localized: "Elliptical", table: "Exercise")
        case .other: return String(localized: "Other exercise", table: "Exercise")
        }
    }
}

/// Use with a Watch Workout start personal automation. The returned identifier
/// can be passed to EndExerciseIntent; an unscoped end never cancels an override.
struct StartExerciseIntent: AppIntent {
    static var title = LocalizedStringResource("Start exercise session", table: "Exercise")
    static var description = IntentDescription(LocalizedStringResource("Log exercise and optionally apply your configured preset for a bounded duration.", table: "Exercise"))

    @Parameter(title: LocalizedStringResource("Activity", table: "Exercise"), default: .other)
    var activity: ExerciseActivity
    @Parameter(title: LocalizedStringResource("Workout start time", table: "Exercise"))
    var startedAt: Date?
    @Parameter(title: LocalizedStringResource("Session identifier", table: "Exercise"))
    var sessionID: String?
    @Parameter(title: LocalizedStringResource("Confirm before applying preset", table: "Exercise"), default: true)
    var confirmBeforeApplying: Bool

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let service = TrioApp.resolver.resolve(ExerciseService.self)!
        if service.journal.configuration.applyPreset, confirmBeforeApplying {
            try await requestConfirmation(result: .result(dialog: IntentDialog(stringLiteral: String(
                localized: "Start exercise with the configured override and time limit?", table: "Exercise"
            ))))
        }
        let id: UUID
        if let sessionID, !sessionID.isEmpty {
            guard let parsed = UUID(uuidString: sessionID) else { throw ExerciseError.invalidConfiguration }
            id = parsed
        } else { id = UUID() }
        let session = try await service.start(activity: activity.rawValue, eventID: id, observedAt: startedAt ?? Date(), source: "shortcut")
        return .result(value: session.id.uuidString, dialog: IntentDialog(stringLiteral: String(localized: "Exercise session recorded. Check Trio for its current status.", table: "Exercise")))
    }
}

struct EndExerciseIntent: AppIntent {
    static var title = LocalizedStringResource("End exercise session", table: "Exercise")
    static var description = IntentDescription(LocalizedStringResource("End only the exercise session with this identifier; preserve newer adjustments.", table: "Exercise"))
    @Parameter(title: LocalizedStringResource("Session identifier", table: "Exercise"))
    var sessionID: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let id = UUID(uuidString: sessionID) else { throw ExerciseError.invalidConfiguration }
        try await TrioApp.resolver.resolve(ExerciseService.self)!.end(sessionID: id)
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Exercise end processed. Newer adjustments were preserved.", table: "Exercise")))
    }
}
