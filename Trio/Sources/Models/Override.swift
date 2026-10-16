import Foundation

struct Override {
    let name: String
    let enabled: Bool
    let date: Date
    let duration: Decimal
    let indefinite: Bool
    let percentage: Double
    let smbIsOff: Bool
    let isPreset: Bool
    let id: String
    let overrideTarget: Bool
    let target: Decimal
    let advancedSettings: Bool
    let isfAndCr: Bool
    let isf: Bool
    let cr: Bool
    let smbIsScheduledOff: Bool
    let start: Decimal
    let end: Decimal
    let smbMinutes: Decimal
    let uamMinutes: Decimal
}

/// Compatibility for persisted overrides created before exercise logging was removed.
struct LegacyExerciseOverrideIdentity: Equatable, Sendable {
    let sessionID: UUID
    let startedAt: Date
    var storedID: String { "trio-exercise:" + sessionID.uuidString }

    static func fromStored(id: String?, start: Date?) -> LegacyExerciseOverrideIdentity? {
        guard let id, id.hasPrefix("trio-exercise:"), let start,
              let uuid = UUID(uuidString: String(id.dropFirst("trio-exercise:".count))) else { return nil }
        return .init(sessionID: uuid, startedAt: start)
    }

    /// Overrides created by the removed feature retain their hard expiry,
    /// even though no exercise UI, session service or Workout action remains.
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
