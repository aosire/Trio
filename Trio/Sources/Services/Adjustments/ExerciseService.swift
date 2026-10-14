import Combine
import Foundation
import Swinject

struct ExerciseOverrideIdentity: Codable, Equatable {
    let sessionID: UUID
    let startedAt: Date
    var storedID: String { "trio-exercise:" + sessionID.uuidString }

    static func fromStored(id: String?, start: Date?) -> ExerciseOverrideIdentity? {
        guard let id, id.hasPrefix("trio-exercise:"), let start,
              let uuid = UUID(uuidString: String(id.dropFirst("trio-exercise:".count))) else { return nil }
        return .init(sessionID: uuid, startedAt: start)
    }

    /// Owned exercise overrides have a hard expiry at the dosing-input boundary,
    /// even when the UI is suspended and no Workout end event arrives.
    static func isEffective(id: String?, start: Date?, duration: Decimal?, indefinite: Bool, now: Date) -> Bool {
        guard id?.hasPrefix("trio-exercise:") == true else { return true }
        guard let id, UUID(uuidString: String(id.dropFirst("trio-exercise:".count))) != nil,
              let start, let duration, !indefinite,
              start.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite,
              NSDecimalNumber(decimal: duration).doubleValue.isFinite,
              duration >= 1, duration <= 240, now >= start
        else { return false }
        return now < start.addingTimeInterval(NSDecimalNumber(decimal: duration).doubleValue * 60)
    }
}

struct ExerciseConfiguration: Codable, Equatable {
    var presetID = ""
    var applyPreset = false
    var durationMinutes = 60

    var isValid: Bool { (1 ... 240).contains(durationMinutes) && (!applyPreset || !presetID.isEmpty) }
}

struct ExerciseSession: Codable, Equatable, Identifiable {
    enum Status: String, Codable { case preparing, active, ended, expired, replaced, failed }
    let id: UUID
    let activity: String
    let source: String
    let startedAt: Date
    let expiresAt: Date
    let appliesPreset: Bool
    let presetID: String
    var status: Status
    var endedAt: Date?
    var identity: ExerciseOverrideIdentity { .init(sessionID: id, startedAt: startedAt) }
    var isOpen: Bool { status == .preparing || status == .active }
}

struct ExerciseJournal: Codable, Equatable {
    var version = 1
    var configuration = ExerciseConfiguration()
    var sessions: [ExerciseSession] = []
    var consumedStarts: [UUID: UUID] = [:]
}

enum ExerciseError: LocalizedError {
    case invalidConfiguration, staleEvent, busy, replaced, duplicateIdentity, unavailableStorage

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return String(localized: "Select a preset and a duration between 1 and 240 minutes.", table: "Exercise")
        case .staleEvent: return String(localized: "This workout start is old or has an invalid time. It was not applied.", table: "Exercise")
        case .busy: return String(localized: "An exercise update is already in progress.", table: "Exercise")
        case .replaced: return String(localized: "The exercise override is no longer the active adjustment.", table: "Exercise")
        case .duplicateIdentity: return String(localized: "This exercise session was already processed.", table: "Exercise")
        case .unavailableStorage: return String(localized: "Exercise records could not be loaded. No exercise override was started.", table: "Exercise")
        }
    }
}

/// Throwing atomic persistence: a failed journal write must not silently start
/// a therapy adjustment that has no durable ownership record.
struct ExerciseJournalStore {
    let url: URL

    func load() throws -> ExerciseJournal {
        guard FileManager.default.fileExists(atPath: url.path) else { return ExerciseJournal() }
        let journal = try JSONDecoder().decode(ExerciseJournal.self, from: Data(contentsOf: url))
        let sessionIDs = Set(journal.sessions.map(\.id))
        guard journal.version == 1, journal.configuration.isValid,
              sessionIDs.count == journal.sessions.count,
              journal.consumedStarts.values.allSatisfy(sessionIDs.contains),
              journal.sessions.filter(\.isOpen).count <= 1,
              journal.sessions.allSatisfy({
                  $0.startedAt.timeIntervalSince1970.isFinite && $0.expiresAt.timeIntervalSince1970.isFinite &&
                      $0.expiresAt.timeIntervalSince($0.startedAt) >= 60 && $0.expiresAt.timeIntervalSince($0.startedAt) <= 240 * 60 &&
                      (!$0.appliesPreset || !$0.presetID.isEmpty)
              })
        else { throw ExerciseError.unavailableStorage }
        return journal
    }

    func save(_ journal: ExerciseJournal) throws {
        try JSONEncoder().encode(journal).write(to: url, options: .atomic)
    }
}

/// Main-actor commands reserve across every suspension. Recovery reconciles
/// persisted intent; it never replays an activation after a process restart.
final class ExerciseService: ObservableObject {
    @Published private(set) var journal: ExerciseJournal
    @Published private(set) var busy = false
    @Published private(set) var lastError: String?
    private let loadFailed: Bool
    private let save: (ExerciseJournal) throws -> Void
    private let activate: @MainActor (ExerciseOverrideIdentity, String, Int, String, String) async throws -> Void
    private let cancel: @MainActor (ExerciseOverrideIdentity) async throws -> Bool
    private let isActive: @MainActor (ExerciseOverrideIdentity) async throws -> Bool
    private let now: () -> Date

    var activeSession: ExerciseSession? { journal.sessions.first(where: \.isOpen) }

    init(
        load: () throws -> ExerciseJournal,
        save: @escaping (ExerciseJournal) throws -> Void,
        activate: @escaping @MainActor (ExerciseOverrideIdentity, String, Int, String, String) async throws -> Void,
        cancel: @escaping @MainActor (ExerciseOverrideIdentity) async throws -> Bool,
        isActive: @escaping @MainActor (ExerciseOverrideIdentity) async throws -> Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.save = save
        self.activate = activate
        self.cancel = cancel
        self.isActive = isActive
        self.now = now
        do {
            journal = try load()
            loadFailed = false
        } catch {
            journal = ExerciseJournal()
            loadFailed = true
            lastError = ExerciseError.unavailableStorage.localizedDescription
        }
    }

    convenience init(resolver: Resolver) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trio-exercise-sessions.json")
        let store = ExerciseJournalStore(url: url)
        self.init(load: store.load, save: store.save, activate: { identity, preset, duration, activity, source in
            try await resolver.resolve(AdjustmentManager.self)!.activateExerciseOverride(
                .presetID(preset), identity: identity, durationMinutes: duration,
                activity: ExerciseActivity(rawValue: activity)?.title ?? activity,
                source: source == "shortcut" ? .shortcut : .app
            )
        }, cancel: { identity in
            try await resolver.resolve(AdjustmentManager.self)!.cancelExerciseOverride(identity, source: .shortcut)
        }, isActive: { identity in
            try await resolver.resolve(AdjustmentManager.self)!.isExerciseOverrideActive(identity)
        })
    }

    @MainActor private func commit(_ updated: ExerciseJournal) throws {
        guard !loadFailed else { throw ExerciseError.unavailableStorage }
        try save(updated)
        journal = updated
    }

    @MainActor func configure(_ configuration: ExerciseConfiguration) throws {
        guard !busy else { throw ExerciseError.busy }
        guard configuration.isValid else { throw ExerciseError.invalidConfiguration }
        var updated = journal
        updated.configuration = configuration
        try commit(updated)
        lastError = nil
    }

    @MainActor func start(activity: String, eventID: UUID, observedAt: Date, source: String = "app") async throws -> ExerciseSession {
        guard !busy else { throw ExerciseError.busy }
        guard !loadFailed else { throw ExerciseError.unavailableStorage }
        busy = true
        defer { busy = false }
        // A repeated identifier remains consumed even after a session ends.
        if let target = journal.consumedStarts[eventID], let existing = journal.sessions.first(where: { $0.id == target }) { return existing }
        if let existing = journal.sessions.first(where: { $0.id == eventID }) { return existing }
        let date = now()
        guard date.timeIntervalSince1970.isFinite, observedAt.timeIntervalSince1970.isFinite,
              date >= observedAt, date.timeIntervalSince(observedAt) <= 120
        else { throw ExerciseError.staleEvent }
        try await reconcile()
        // Duplicate Workout starts do not restart or extend the current mode.
        if let activeSession {
            var updated = journal
            updated.consumedStarts[eventID] = activeSession.id
            try commit(updated)
            return activeSession
        }
        let configuration = journal.configuration
        guard configuration.isValid else { throw ExerciseError.invalidConfiguration }
        var session = ExerciseSession(
            id: eventID, activity: activity, source: source, startedAt: date,
            expiresAt: date.addingTimeInterval(Double(configuration.durationMinutes) * 60),
            appliesPreset: configuration.applyPreset, presetID: configuration.presetID,
            status: configuration.applyPreset ? .preparing : .active
        )
        var updated = journal
        updated.sessions.insert(session, at: 0)
        updated.consumedStarts[eventID] = session.id
        try commit(updated)
        if configuration.applyPreset {
            do {
                try await activate(session.identity, configuration.presetID, configuration.durationMinutes, activity, source)
            } catch {
                updated.sessions[0].status = .failed
                updated.sessions[0].endedAt = now()
                try commit(updated)
                lastError = error.localizedDescription
                throw error
            }
            session.status = .active
            updated.sessions[0] = session
            // If this write fails, the durable preparing record still owns the
            // bounded override. Reconciliation queries it; no blind retry.
            try commit(updated)
        }
        lastError = nil
        return session
    }

    @MainActor func end(sessionID: UUID) async throws {
        guard !busy else { throw ExerciseError.busy }
        busy = true
        defer { busy = false }
        guard let index = journal.sessions.firstIndex(where: { $0.id == sessionID }), journal.sessions[index].isOpen else { return }
        let session = journal.sessions[index]
        let endedOwned = session.appliesPreset ? try await cancel(session.identity) : true
        var updated = journal
        updated.sessions[index].status = endedOwned ? .ended : .replaced
        updated.sessions[index].endedAt = min(now(), session.expiresAt)
        try commit(updated)
        lastError = nil
    }

    @MainActor func refresh() async {
        guard !busy, !loadFailed else { return }
        busy = true
        defer { busy = false }
        do { try await reconcile(); lastError = nil } catch { lastError = error.localizedDescription }
    }

    @MainActor private func reconcile() async throws {
        guard let index = journal.sessions.firstIndex(where: \.isOpen) else { return }
        let session = journal.sessions[index]
        var updated = journal
        let date = now()
        guard date.timeIntervalSince1970.isFinite, date >= session.startedAt else { throw ExerciseError.staleEvent }
        if session.appliesPreset {
            let owned = try await isActive(session.identity)
            if !owned {
                updated.sessions[index].status = .replaced
                updated.sessions[index].endedAt = min(date, session.expiresAt)
            } else if date >= session.expiresAt {
                let endedOwned = try await cancel(session.identity)
                updated.sessions[index].status = endedOwned ? .expired : .replaced
                updated.sessions[index].endedAt = session.expiresAt
            } else {
                updated.sessions[index].status = .active
            }
        } else if date >= session.expiresAt {
            updated.sessions[index].status = .expired
            updated.sessions[index].endedAt = session.expiresAt
        }
        if updated != journal { try commit(updated) }
    }
}
