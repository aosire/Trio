import Foundation
import Testing

@testable import Trio

@Suite("Removed exercise feature compatibility") struct LegacyExerciseOverrideTests {
    @Test("Existing owned rows expire without a session service or visible UI") func expiry() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let identity = LegacyExerciseOverrideIdentity(sessionID: UUID(), startedAt: start)
        func effective(_ date: Date, duration: Decimal? = 30, indefinite: Bool = false, id: String? = nil) -> Bool {
            LegacyExerciseOverrideIdentity.isEffective(
                id: id ?? identity.storedID, start: start, duration: duration, indefinite: indefinite, now: date
            )
        }
        #expect(effective(start))
        #expect(effective(start.addingTimeInterval(1799)))
        #expect(!effective(start.addingTimeInterval(1800)))
        #expect(!effective(start.addingTimeInterval(-1)))
        #expect(!effective(start, duration: nil))
        #expect(!effective(start, duration: .nan))
        #expect(!effective(start, indefinite: true))
        #expect(!effective(start, duration: 0))
        #expect(!effective(start, duration: 241))
        #expect(!effective(start, id: "trio-exercise:invalid"))
        #expect(effective(start, duration: nil, indefinite: true, id: "ordinary-manual-override"))
    }

    @Test("Legacy receipt parsing never claims an ordinary manual override") func identity() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let id = LegacyExerciseOverrideIdentity(sessionID: UUID(), startedAt: start)
        #expect(LegacyExerciseOverrideIdentity.fromStored(id: id.storedID, start: start) == id)
        #expect(LegacyExerciseOverrideIdentity.fromStored(id: id.storedID, start: nil) == nil)
        #expect(LegacyExerciseOverrideIdentity.fromStored(id: "trio-exercise:invalid", start: start) == nil)
        #expect(LegacyExerciseOverrideIdentity.fromStored(id: UUID().uuidString, start: start) == nil)
    }
}
