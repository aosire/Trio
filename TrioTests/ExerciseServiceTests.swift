import Foundation
import Testing
@testable import Trio

@Suite("Exercise session coordination") @MainActor struct ExerciseServiceTests {
    private enum Failure: Error { case disk, activation, connection }

    @MainActor private final class Latch {
        private var openFlag = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if openFlag { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func open() {
            openFlag = true
            let pending = waiters
            waiters = []
            pending.forEach { $0.resume() }
        }
    }

    @MainActor private final class Harness {
        var stored = ExerciseJournal()
        var time = Date(timeIntervalSince1970: 1700000000)
        var owned: ExerciseOverrideIdentity?
        var activations = 0
        var cancellations = 0
        var saves = 0
        var failSaves: Set<Int> = []
        var failActivation = false
        var failCancel = false
        var durableBeforeActivation = false
        var entered: Latch?
        var release: Latch?

        init(mode: Bool = true) {
            stored.configuration = ExerciseConfiguration(presetID: mode ? "selected-preset" : "", applyPreset: mode, durationMinutes: 30)
        }

        func service() -> ExerciseService {
            ExerciseService(load: { self.stored }, save: {
                self.saves += 1
                if self.failSaves.contains(self.saves) { throw Failure.disk }
                self.stored = $0
            }, activate: { identity, preset, duration, _, _ in
                self.activations += 1
                self.durableBeforeActivation = self.stored.sessions.first?.identity == identity && self.stored.sessions.first?.status == .preparing
                #expect(preset == "selected-preset")
                #expect(duration == 30)
                self.entered?.open()
                if let release = self.release { await release.wait() }
                if self.failActivation { throw Failure.activation }
                self.owned = identity
            }, cancel: { identity in
                self.cancellations += 1
                if self.failCancel { throw Failure.connection }
                guard self.owned == identity else { return false }
                self.owned = nil
                return true
            }, isActive: { self.owned == $0 }, now: { self.time })
        }
    }

    @Test("Default configuration logs without changing therapy") func loggingOnly() async throws {
        #expect(!ExerciseConfiguration().applyPreset)
        let h = Harness(mode: false)
        let manual = ExerciseOverrideIdentity(sessionID: UUID(), startedAt: h.time)
        h.owned = manual
        let service = h.service()
        let session = try await service.start(activity: "indoorWalk", eventID: UUID(), observedAt: h.time)
        #expect(session.status == .active)
        #expect(!session.appliesPreset)
        #expect(h.activations == 0)
        try await service.end(sessionID: session.id)
        #expect(h.cancellations == 0)
        #expect(h.owned == manual)
        #expect(service.journal.sessions.first?.status == .ended)
    }

    @Test("Ownership is persisted before the selected bounded preset is activated") func durableStart() async throws {
        let h = Harness()
        let service = h.service()
        let session = try await service.start(activity: "elliptical", eventID: UUID(), observedAt: h.time, source: "shortcut")
        #expect(h.durableBeforeActivation)
        #expect(h.activations == 1)
        #expect(session.expiresAt == h.time.addingTimeInterval(1800))
        #expect(session.source == "shortcut")
        #expect(h.owned == session.identity)
        #expect(h.stored == service.journal)
    }

    @Test("Duplicate session identifiers never restart or extend exercise") func sameIdentifier() async throws {
        let h = Harness()
        let service = h.service()
        let id = UUID()
        let first = try await service.start(activity: "indoorWalk", eventID: id, observedAt: h.time)
        h.time = h.time.addingTimeInterval(60)
        let second = try await service.start(activity: "elliptical", eventID: id, observedAt: h.time)
        #expect(second == first)
        #expect(h.activations == 1)
        #expect(service.journal.sessions.count == 1)
    }

    @Test("Coalesced starts remain consumed after manual termination") func coalescedIdentifiers() async throws {
        let h = Harness()
        let service = h.service()
        let first = try await service.start(activity: "indoorWalk", eventID: UUID(), observedAt: h.time)
        let alias = UUID()
        let duplicate = try await service.start(activity: "indoorWalk", eventID: alias, observedAt: h.time)
        #expect(duplicate.id == first.id)
        try await service.end(sessionID: first.id)
        let replay = try await service.start(activity: "indoorWalk", eventID: alias, observedAt: h.time)
        #expect(replay.status == .ended)
        #expect(h.activations == 1)
        #expect(service.journal.sessions.count == 1)
    }

    @Test("Old and future workout starts cannot become dosing instructions") func staleStarts() async throws {
        let h = Harness()
        let service = h.service()
        for date in [h.time.addingTimeInterval(-121), h.time.addingTimeInterval(1), Date(timeIntervalSince1970: .infinity)] {
            await #expect(throws: ExerciseError.self) { try await service.start(activity: "indoorWalk", eventID: UUID(), observedAt: date) }
        }
        #expect(h.activations == 0)
        #expect(service.journal.sessions.isEmpty)
    }

    @Test("Invalid configuration cannot be saved") func invalidConfiguration() throws {
        let h = Harness()
        let service = h.service()
        for config in [ExerciseConfiguration(presetID: "", applyPreset: true, durationMinutes: 30),
                       ExerciseConfiguration(presetID: "selected-preset", applyPreset: true, durationMinutes: 0),
                       ExerciseConfiguration(presetID: "selected-preset", applyPreset: true, durationMinutes: 241)] {
            #expect(throws: ExerciseError.self) { try service.configure(config) }
        }
        #expect(h.saves == 0)
    }

    @Test("Concurrent starts cannot issue overlapping activations") func concurrentStarts() async throws {
        let h = Harness()
        let entered = Latch()
        let release = Latch()
        h.entered = entered
        h.release = release
        let service = h.service()
        let first = Task { @MainActor in try await service.start(activity: "indoorWalk", eventID: UUID(), observedAt: h.time) }
        await entered.wait()
        await #expect(throws: ExerciseError.self) { try await service.start(activity: "indoorWalk", eventID: UUID(), observedAt: h.time) }
        #expect(h.activations == 1)
        release.open()
        _ = try await first.value
        #expect(!service.busy)
    }

    @Test("Ending exercise preserves a replacement manual override") func replacement() async throws {
        let h = Harness()
        let service = h.service()
        let session = try await service.start(activity: "elliptical", eventID: UUID(), observedAt: h.time)
        let manual = ExerciseOverrideIdentity(sessionID: UUID(), startedAt: h.time)
        h.owned = manual
        try await service.end(sessionID: session.id)
        #expect(h.owned == manual)
        #expect(service.journal.sessions.first?.status == .replaced)
    }

    @Test("An old end event cannot terminate a later exercise session") func oldEnd() async throws {
        let h = Harness()
        let service = h.service()
        let first = try await service.start(activity: "indoorWalk", eventID: UUID(), observedAt: h.time)
        try await service.end(sessionID: first.id)
        h.time = h.time.addingTimeInterval(1)
        let second = try await service.start(activity: "elliptical", eventID: UUID(), observedAt: h.time)
        try await service.end(sessionID: first.id)
        #expect(h.owned == second.identity)
        #expect(h.cancellations == 1)
    }

    @Test("Expiry ends only the owned adjustment and is idempotent") func expiry() async throws {
        let h = Harness()
        let service = h.service()
        let session = try await service.start(activity: "elliptical", eventID: UUID(), observedAt: h.time)
        h.time = session.expiresAt
        await service.refresh()
        await service.refresh()
        #expect(h.owned == nil)
        #expect(h.cancellations == 1)
        #expect(service.journal.sessions.first?.status == .expired)
        #expect(service.journal.sessions.first?.endedAt == session.expiresAt)
    }

    @Test("Manual replacement reconciliation sends no cancellation") func replacementRefresh() async throws {
        let h = Harness()
        let service = h.service()
        _ = try await service.start(activity: "elliptical", eventID: UUID(), observedAt: h.time)
        let manual = ExerciseOverrideIdentity(sessionID: UUID(), startedAt: h.time)
        h.owned = manual
        await service.refresh()
        #expect(h.owned == manual)
        #expect(h.cancellations == 0)
        #expect(service.activeSession == nil)
    }

    @Test("Restart recovery reconciles preparing ownership without replaying activation") func restartOwned() async throws {
        let h = Harness()
        let original = h.service()
        _ = try await original.start(activity: "elliptical", eventID: UUID(), observedAt: h.time)
        h.stored.sessions[0].status = .preparing
        let restarted = h.service()
        await restarted.refresh()
        #expect(restarted.activeSession?.status == .active)
        #expect(h.activations == 1)
    }

    @Test("A preparing record without an owned override is never replayed") func restartNotApplied() async throws {
        let h = Harness()
        _ = try await h.service().start(activity: "elliptical", eventID: UUID(), observedAt: h.time)
        h.stored.sessions[0].status = .preparing
        h.owned = nil
        let restarted = h.service()
        await restarted.refresh()
        #expect(restarted.activeSession == nil)
        #expect(h.activations == 1)
    }

    @Test("Persistence failure before activation changes no therapy") func diskBeforeActivation() async {
        let h = Harness()
        h.failSaves = [1]
        let service = h.service()
        await #expect(throws: Failure.self) { try await service.start(activity: "elliptical", eventID: UUID(), observedAt: h.time) }
        #expect(h.activations == 0)
        #expect(h.owned == nil)
        #expect(service.activeSession == nil)
    }

    @Test("Persistence failure after activation retains durable ownership for recovery") func diskAfterActivation() async throws {
        let h = Harness()
        h.failSaves = [2]
        let service = h.service()
        await #expect(throws: Failure.self) { try await service.start(activity: "elliptical", eventID: UUID(), observedAt: h.time) }
        #expect(h.owned != nil)
        #expect(h.stored.sessions.first?.status == .preparing)
        h.failSaves = []
        let restarted = h.service()
        await restarted.refresh()
        #expect(restarted.activeSession?.status == .active)
        #expect(h.activations == 1)
    }

    @Test("Failed activation remains visible and its event cannot replay") func activationFailure() async throws {
        let h = Harness()
        h.failActivation = true
        let service = h.service()
        let id = UUID()
        await #expect(throws: Failure.self) { try await service.start(activity: "elliptical", eventID: id, observedAt: h.time) }
        #expect(service.journal.sessions.first?.status == .failed)
        #expect(h.owned == nil)
        _ = try await service.start(activity: "elliptical", eventID: id, observedAt: h.time)
        #expect(h.activations == 1)
    }

    @Test("Failed cancellation retains the session and permits a deliberate retry") func endFailure() async throws {
        let h = Harness()
        let service = h.service()
        let session = try await service.start(activity: "elliptical", eventID: UUID(), observedAt: h.time)
        h.failCancel = true
        await #expect(throws: Failure.self) { try await service.end(sessionID: session.id) }
        #expect(service.activeSession?.id == session.id)
        #expect(h.owned == session.identity)
        h.failCancel = false
        try await service.end(sessionID: session.id)
        #expect(service.activeSession == nil)
    }

    @Test("Corrupt or unavailable loaded state blocks new mode activation") func loadFailure() async {
        var calls = 0
        let service = ExerciseService(load: { throw Failure.disk }, save: { _ in Issue.record("Corrupt history was overwritten") },
            activate: { _, _, _, _, _ in calls += 1 }, cancel: { _ in false }, isActive: { _ in false })
        await #expect(throws: ExerciseError.self) { try await service.start(activity: "elliptical", eventID: UUID(), observedAt: Date()) }
        #expect(calls == 0)
        #expect(service.lastError != nil)
    }

    @Test("Atomic journal storage round-trips configuration, ownership and consumed IDs") func persistence() async throws {
        let h = Harness()
        _ = try await h.service().start(activity: "elliptical", eventID: UUID(), observedAt: h.time)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ExerciseJournalStore(url: url)
        try store.save(h.stored)
        #expect(try store.load() == h.stored)
        try Data("{broken".utf8).write(to: url)
        #expect(throws: DecodingError.self) { try store.load() }
    }

    @Test("Dosing input expiry is independent of UI and missed end events") func dosingExpiry() {
        let start = Date(timeIntervalSince1970: 1700000000)
        let identity = ExerciseOverrideIdentity(sessionID: UUID(), startedAt: start)
        func effective(_ date: Date, duration: Decimal? = 30, indefinite: Bool = false, id: String? = nil) -> Bool {
            ExerciseOverrideIdentity.isEffective(id: id ?? identity.storedID, start: start, duration: duration, indefinite: indefinite, now: date)
        }
        #expect(effective(start))
        #expect(effective(start.addingTimeInterval(1799)))
        #expect(!effective(start.addingTimeInterval(1800)))
        #expect(!effective(start.addingTimeInterval(-1)))
        #expect(!effective(start, duration: nil))
        #expect(!effective(start, duration: .nan))
        #expect(!effective(start, indefinite: true))
        #expect(!effective(start, duration: 241))
        #expect(!effective(start, id: "trio-exercise:invalid"))
        #expect(effective(start, duration: nil, indefinite: true, id: "ordinary-manual-override"))
    }
}
