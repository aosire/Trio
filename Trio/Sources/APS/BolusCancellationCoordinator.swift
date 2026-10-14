import Combine
import Foundation
import LoopKit

enum BolusCancellationState: Equatable {
    case idle
    case cancelling
    case retrying
    case unconfirmed
    case stopped
    case failed(String)

    var isPending: Bool {
        switch self {
        case .cancelling, .retrying, .unconfirmed: return true
        case .idle, .stopped, .failed: return false
        }
    }
}

enum BolusCancellationError: LocalizedError {
    case pumpChanged
    case noPump

    var errorDescription: String? {
        switch self {
        case .pumpChanged:
            return String(localized: "The pump or bolus changed. The original cancellation could not be confirmed.", table: "BolusCancellation")
        case .noPump:
            return String(localized: "No pump is connected. Bolus cancellation could not be confirmed.", table: "BolusCancellation")
        }
    }
}

/// Retry identity comes from the pump's dose, never the UI's last history row.
/// A `.noBolus` cache entry is not treated as an acknowledgement; the driver
/// still receives the stop request. A different in-progress dose is rejected.
struct BolusCancellationContext {
    let pumpID: ObjectIdentifier
    let activationDate: Date?
    let doseStart: Date?

    init(pumpID: ObjectIdentifier, activationDate: Date?, bolusState: PumpManagerStatus.BolusState) {
        self.pumpID = pumpID
        self.activationDate = activationDate
        if case let .inProgress(dose) = bolusState {
            doseStart = dose.startDate
        } else {
            doseStart = nil
        }
    }

    func matches(pumpID: ObjectIdentifier?, activationDate: Date?, bolusState: PumpManagerStatus.BolusState) -> Bool {
        guard self.pumpID == pumpID, self.activationDate == activationDate else { return false }
        switch bolusState {
        case let .inProgress(dose): return dose.startDate == doseStart
        case .initiating: return false
        case .canceling, .noBolus: return true
        }
    }
}

/// One in-flight stop request shared by every cancellation entry point.
/// Only the driver callback confirms success. A slow callback keeps the request
/// reserved: a warning must never release it and start a second pump command.
final class BolusCancellationCoordinator {
    typealias Outcome = Result<Void, Error>

    let state = CurrentValueSubject<BolusCancellationState, Never>(.idle)
    @MainActor private(set) var activeTask: Task<Outcome, Never>?
    @MainActor private var requestID: UUID?

    @MainActor @discardableResult func request(
        mayCancel: @escaping @MainActor () -> Bool,
        cancel: @escaping @MainActor () async throws -> Void,
        shouldRetry: @escaping @MainActor (Error) -> Bool,
        maxAttempts: Int = 3,
        retryDelay: @escaping @MainActor () async throws -> Void = { try await Task.sleep(nanoseconds: 500_000_000) },
        warningDelay: @escaping @MainActor () async throws -> Void = { try await Task.sleep(nanoseconds: 10_000_000_000) },
        onUnconfirmed: @escaping @MainActor () -> Void = {},
        onCompletion: @escaping @MainActor (Outcome) -> Void = { _ in }
    ) -> Task<Outcome, Never> {
        if let activeTask { return activeTask }

        let id = UUID()
        requestID = id
        let task = Task { @MainActor in
            let warning = Task { @MainActor in
                do { try await warningDelay() } catch { return }
                guard !Task.isCancelled, self.requestID == id else { return }
                self.state.send(.unconfirmed)
                onUnconfirmed()
            }
            defer { warning.cancel() }

            var outcome: Outcome = .failure(BolusCancellationError.pumpChanged)
            for attempt in 1 ... max(1, maxAttempts) {
                guard mayCancel() else {
                    outcome = .failure(BolusCancellationError.pumpChanged)
                    break
                }
                do {
                    try await cancel()
                    guard mayCancel() else { throw BolusCancellationError.pumpChanged }
                    outcome = .success(())
                    break
                } catch {
                    outcome = .failure(error)
                    guard attempt < maxAttempts, shouldRetry(error) else { break }
                    // Keep the same reservation while waiting. Never retarget a retry
                    // to a new pump or a different bolus after this suspension.
                    if self.state.value != .unconfirmed { self.state.send(.retrying) }
                    do { try await retryDelay() } catch {
                        outcome = .failure(error)
                        break
                    }
                }
            }

            self.requestID = nil
            // Complete side effects before publishing a terminal state that can
            // synchronously cause a subscriber to start another request.
            onCompletion(outcome)
            self.activeTask = nil
            switch outcome {
            case .success: self.state.send(.stopped)
            case let .failure(error): self.state.send(.failed(error.localizedDescription))
            }
            return outcome
        }
        activeTask = task
        // Reserve first: synchronous publisher subscribers may re-enter request().
        // This still acknowledges the tap before any pump I/O can start.
        state.send(.cancelling)
        return task
    }

    @MainActor func dismissResult() {
        guard activeTask == nil else { return }
        state.send(.idle)
    }

    /// Omnipod's driver resolves its pending stop command before another attempt.
    /// Other drivers must opt in only after their retry semantics are verified.
    static func isRetryableOmnipodError(_ error: Error) -> Bool {
        guard let error = error as? PumpManagerError else { return false }
        switch error {
        case .communication, .connection: return true
        case .configuration, .deviceState, .uncertainDelivery: return false
        }
    }
}
