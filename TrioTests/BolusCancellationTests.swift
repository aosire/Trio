import Combine
import Foundation
import LoopKit
import Testing
@testable import Trio

@Suite("Bolus cancellation") @MainActor struct BolusCancellationTests {
    private enum TestError: Error { case disconnected, rejected }

    @Test("Leaving a cancellation view clears only the pump-confirmed success") func leaveAfterSuccess() async {
        let coordinator = BolusCancellationCoordinator()
        let task = coordinator.request(mayCancel: { true }, cancel: {}, shouldRetry: { _ in false })
        _ = await task.value
        #expect(coordinator.state.value == .stopped)
        coordinator.dismissStoppedResult()
        #expect(coordinator.state.value == .idle)
        #expect(coordinator.retryLastRequest() == nil)
        coordinator.dismissStoppedResult()
        #expect(coordinator.state.value == .idle)
    }

    @Test("Leaving while cancellation is pending preserves the command reservation") func leaveWhilePending() async {
        let coordinator = BolusCancellationCoordinator()
        let entered = Latch()
        let release = Latch()
        var commands = 0
        let task = coordinator.request(mayCancel: { true }, cancel: {
            commands += 1
            entered.open()
            await release.wait()
        }, shouldRetry: { _ in false })
        await entered.wait()
        coordinator.dismissStoppedResult()
        #expect(coordinator.state.value == .cancelling)
        #expect(coordinator.activeTask != nil)
        release.open()
        _ = await task.value
        #expect(commands == 1)
        #expect(coordinator.state.value == .stopped)
    }

    @Test("Leaving an unconfirmed cancellation never hides its uncertainty warning") func leaveWhileUnconfirmed() async {
        let coordinator = BolusCancellationCoordinator()
        let release = Latch()
        let warned = Latch()
        let task = coordinator.request(mayCancel: { true }, cancel: { await release.wait() }, shouldRetry: { _ in false },
            warningDelay: {}, onUnconfirmed: { warned.open() })
        await warned.wait()
        coordinator.dismissStoppedResult()
        #expect(coordinator.state.value == .unconfirmed)
        #expect(coordinator.activeTask != nil)
        release.open()
        _ = await task.value
    }

    @Test("A stale success-view disappearance preserves a later failure and its retry") func staleLeaveAfterFailure() async {
        let coordinator = BolusCancellationCoordinator()
        _ = await coordinator.request(mayCancel: { true }, cancel: {}, shouldRetry: { _ in false }).value
        var fail = true
        let failure = coordinator.request(mayCancel: { true }, cancel: {
            if fail { throw TestError.rejected }
        }, shouldRetry: { _ in false })
        _ = await failure.value
        let warning = coordinator.state.value
        coordinator.dismissStoppedResult()
        #expect(coordinator.state.value == warning)
        if case .failed = warning {} else { Issue.record("Expected an explicit failure") }
        fail = false
        let retry = coordinator.retryLastRequest()
        #expect(retry != nil)
        _ = await retry?.value
        #expect(coordinator.state.value == .stopped)
    }

    /// A deterministic async boundary: no sleeps or timing-based assertions.
    @MainActor private final class Latch {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    @Test("One tap acknowledges synchronously and waits for the driver") func acknowledgesBeforePumpIO() async {
        let coordinator = BolusCancellationCoordinator()
        let entered = Latch()
        let release = Latch()
        var calls = 0
        let task = coordinator.request(mayCancel: { true }, cancel: {
            calls += 1
            entered.open()
            await release.wait()
        }, shouldRetry: { _ in false })

        #expect(coordinator.state.value == .cancelling)
        #expect(calls == 0)
        await entered.wait()
        #expect(coordinator.state.value.isPending)
        coordinator.dismissResult()
        #expect(coordinator.state.value.isPending)
        release.open()
        _ = await task.value
        #expect(coordinator.state.value == .stopped)
        #expect(calls == 1)
    }

    @Test("Repeated taps share one request and one completion") func repeatedTapsCoalesce() async {
        let coordinator = BolusCancellationCoordinator()
        let release = Latch()
        var calls = 0
        var completions = 0
        let first = coordinator.request(mayCancel: { true }, cancel: {
            calls += 1
            await release.wait()
        }, shouldRetry: { _ in false }, onCompletion: { _ in completions += 1 })
        let second = coordinator.request(mayCancel: { true }, cancel: {
            Issue.record("A duplicate request reached the pump")
        }, shouldRetry: { _ in false }, onCompletion: { _ in
            Issue.record("A duplicate request produced a second completion")
        })
        release.open()
        _ = await first.value
        _ = await second.value
        #expect(calls == 1)
        #expect(completions == 1)
    }

    @Test("A synchronous state subscriber cannot create a second command") func reentrantTapCoalesces() async {
        let coordinator = BolusCancellationCoordinator()
        var duplicate: Task<BolusCancellationCoordinator.Outcome, Never>?
        var calls = 0
        let subscription = coordinator.state.sink { state in
            guard state == .cancelling else { return }
            duplicate = coordinator.request(mayCancel: { true }, cancel: {
                Issue.record("Reentrant cancellation reached the pump")
            }, shouldRetry: { _ in false })
        }
        let task = coordinator.request(mayCancel: { true }, cancel: { calls += 1 }, shouldRetry: { _ in false })
        _ = await task.value
        _ = await duplicate?.value
        #expect(calls == 1)
        withExtendedLifetime(subscription) {}
    }

    @Test("A communication failure is retried without another tap") func retriesThenStops() async {
        let coordinator = BolusCancellationCoordinator()
        var calls = 0
        var states: [BolusCancellationState] = []
        let subscription = coordinator.state.sink { states.append($0) }
        let task = coordinator.request(mayCancel: { true }, cancel: {
            calls += 1
            if calls == 1 { throw TestError.disconnected }
        }, shouldRetry: { _ in true }, retryDelay: {})
        _ = await task.value
        #expect(calls == 2)
        #expect(states.contains(.retrying))
        #expect(coordinator.state.value == .stopped)
        withExtendedLifetime(subscription) {}
    }

    @Test("Retries are bounded and failure remains visible") func boundedFailure() async {
        let coordinator = BolusCancellationCoordinator()
        var calls = 0
        let task = coordinator.request(mayCancel: { true }, cancel: {
            calls += 1
            throw TestError.disconnected
        }, shouldRetry: { _ in true }, retryDelay: {})
        _ = await task.value
        #expect(calls == 3)
        if case .failed = coordinator.state.value {} else { Issue.record("Failure was hidden") }
        #expect(!coordinator.state.value.isPending)
        coordinator.dismissResult()
        #expect(coordinator.state.value == .idle)
        #expect(calls == 3, "Dismissing a warning must not send a pump command")
        #expect(coordinator.retryLastRequest() == nil, "An old Retry control must not survive dismissal or a new bolus")
    }

    @Test("Configuration/state failures do not retry") func doesNotRetryRejectedStop() async {
        let coordinator = BolusCancellationCoordinator()
        var calls = 0
        let task = coordinator.request(mayCancel: { true }, cancel: {
            calls += 1
            throw TestError.rejected
        }, shouldRetry: { _ in false })
        _ = await task.value
        #expect(calls == 1)
        if case .failed = coordinator.state.value {} else { Issue.record("Stop was reported as successful") }
    }

    @Test("Changed pump or bolus prevents the initial command") func changedBeforeSend() async {
        let coordinator = BolusCancellationCoordinator()
        let task = coordinator.request(mayCancel: { false }, cancel: {
            Issue.record("A different pump/bolus received the cancellation")
        }, shouldRetry: { _ in false })
        _ = await task.value
        if case .failed = coordinator.state.value {} else { Issue.record("Expected an explicit failure") }
    }

    @Test("A retry must not cancel a later bolus or replacement pod") func changedWhileWaiting() async {
        let coordinator = BolusCancellationCoordinator()
        let waiting = Latch()
        let retry = Latch()
        var isOriginal = true
        var calls = 0
        let task = coordinator.request(mayCancel: { isOriginal }, cancel: {
            calls += 1
            throw TestError.disconnected
        }, shouldRetry: { _ in true }, retryDelay: {
            waiting.open()
            await retry.wait()
        })
        await waiting.wait()
        isOriginal = false
        retry.open()
        _ = await task.value
        #expect(calls == 1)
        if case .failed = coordinator.state.value {} else { Issue.record("Expected an explicit failure") }
    }

    @Test("Late acknowledgement cannot claim a changed pump stopped") func changedDuringCommand() async {
        let coordinator = BolusCancellationCoordinator()
        var isOriginal = true
        let task = coordinator.request(mayCancel: { isOriginal }, cancel: {
            isOriginal = false
        }, shouldRetry: { _ in false })
        _ = await task.value
        if case .failed = coordinator.state.value {} else { Issue.record("New pump/bolus was shown as stopped") }
    }

    @Test("A missing callback warns but does not release the command reservation") func delayedAcknowledgement() async {
        let coordinator = BolusCancellationCoordinator()
        let started = Latch()
        let release = Latch()
        let warning = Latch()
        let warned = Latch()
        var calls = 0
        var warnings = 0
        let task = coordinator.request(mayCancel: { true }, cancel: {
            calls += 1
            started.open()
            await release.wait()
        }, shouldRetry: { _ in false }, warningDelay: { await warning.wait() }, onUnconfirmed: {
            warnings += 1
            warned.open()
        })
        await started.wait()
        warning.open()
        await warned.wait()
        #expect(coordinator.state.value == .unconfirmed)
        coordinator.dismissResult()
        #expect(coordinator.state.value.isPending)
        let duplicate = coordinator.request(mayCancel: { true }, cancel: {
            Issue.record("A warning released an unacknowledged command")
        }, shouldRetry: { _ in false })
        release.open()
        _ = await task.value
        _ = await duplicate.value
        #expect(calls == 1)
        #expect(warnings == 1)
        #expect(coordinator.state.value == .stopped)
    }

    @Test("An old watchdog cannot overwrite a finished request or a new request") func oldWarningCannotLeak() async {
        let coordinator = BolusCancellationCoordinator()
        let warning = Latch()
        let first = coordinator.request(mayCancel: { true }, cancel: {}, shouldRetry: { _ in false }, warningDelay: {
            await warning.wait()
        }, onUnconfirmed: { Issue.record("An old watchdog escaped its request") })
        _ = await first.value
        coordinator.dismissResult()
        let second = coordinator.request(mayCancel: { true }, cancel: {}, shouldRetry: { _ in false })
        warning.open()
        // The old watchdog may have been cancelled before it ever started.
        _ = await second.value
        #expect(coordinator.state.value == .stopped)
    }

    @Test("A failed stop can be explicitly retried") func manualRetryAfterFailure() async {
        let coordinator = BolusCancellationCoordinator()
        var rejects = true
        let first = coordinator.request(mayCancel: { true }, cancel: {
            if rejects { throw TestError.rejected }
        }, shouldRetry: { _ in false })
        _ = await first.value
        rejects = false
        let retry = coordinator.retryLastRequest()
        #expect(retry != nil)
        #expect(coordinator.state.value == .cancelling)
        _ = await retry?.value
        #expect(coordinator.state.value == .stopped)
        coordinator.dismissResult()
        #expect(coordinator.state.value == .idle)
    }

    @Test("The visible Retry action retains the original bolus context") func manualRetryCannotRetarget() async {
        let coordinator = BolusCancellationCoordinator()
        var isOriginal = true
        var calls = 0
        let first = coordinator.request(mayCancel: { isOriginal }, cancel: {
            calls += 1
            throw TestError.rejected
        }, shouldRetry: { _ in false })
        _ = await first.value
        isOriginal = false
        let retry = coordinator.retryLastRequest()
        #expect(retry != nil)
        _ = await retry?.value
        #expect(calls == 1, "A later bolus must not receive the old Retry request")
        if case .failed = coordinator.state.value {} else { Issue.record("Changed context should remain unconfirmed") }
    }

    @Test("Only verified communication/connection errors opt into Omnipod retries") func retryPolicy() {
        #expect(BolusCancellationCoordinator.isRetryableOmnipodError(PumpManagerError.communication(nil)))
        #expect(BolusCancellationCoordinator.isRetryableOmnipodError(PumpManagerError.connection(nil)))
        #expect(!BolusCancellationCoordinator.isRetryableOmnipodError(PumpManagerError.configuration(nil)))
        #expect(!BolusCancellationCoordinator.isRetryableOmnipodError(PumpManagerError.deviceState(nil)))
        #expect(!BolusCancellationCoordinator.isRetryableOmnipodError(PumpManagerError.uncertainDelivery))
        #expect(!BolusCancellationCoordinator.isRetryableOmnipodError(TestError.disconnected))
    }

    @Test("A driver cancelling state must not remove the active-bolus UI") func cancellingIsNotStopped() {
        #expect(BolusStatus(pumpState: .canceling) == .inProgress)
        #expect(BolusStatus(pumpState: .initiating) == .initiating)
        #expect(BolusStatus(pumpState: .noBolus) == .noBolus)
    }

    private func dose(start: Date, units: Double = 2) -> DoseEntry {
        DoseEntry(type: .bolus, startDate: start, endDate: start.addingTimeInterval(60), value: units, unit: .units)
    }

    @Test("Dose identity survives the driver's cancelling state and partial delivery") func sameDoseIdentity() {
        let pump = NSObject()
        let start = Date(timeIntervalSince1970: 1000)
        let activation = start.addingTimeInterval(-3600)
        let context = BolusCancellationContext(
            pumpID: ObjectIdentifier(pump), activationDate: activation, bolusState: .inProgress(dose(start: start))
        )
        #expect(context.matches(pumpID: ObjectIdentifier(pump), activationDate: activation, bolusState: .canceling))
        #expect(context.matches(pumpID: ObjectIdentifier(pump), activationDate: activation, bolusState: .inProgress(dose(start: start, units: 0.5))))
        #expect(context.matches(pumpID: ObjectIdentifier(pump), activationDate: activation, bolusState: .noBolus))
    }

    @Test("A later bolus and an initiating dose cannot receive an old retry") func laterDoseIdentity() {
        let pump = NSObject()
        let start = Date(timeIntervalSince1970: 1000)
        let context = BolusCancellationContext(pumpID: ObjectIdentifier(pump), activationDate: nil, bolusState: .inProgress(dose(start: start)))
        #expect(!context.matches(pumpID: ObjectIdentifier(pump), activationDate: nil, bolusState: .inProgress(dose(start: start.addingTimeInterval(1)))))
        #expect(!context.matches(pumpID: ObjectIdentifier(pump), activationDate: nil, bolusState: .initiating))
    }

    @Test("Pump replacement and a new pod invalidate the captured context") func replacementIdentity() {
        let pump = NSObject()
        let replacement = NSObject()
        let start = Date(timeIntervalSince1970: 1000)
        let context = BolusCancellationContext(pumpID: ObjectIdentifier(pump), activationDate: start, bolusState: .inProgress(dose(start: start)))
        #expect(!context.matches(pumpID: ObjectIdentifier(replacement), activationDate: start, bolusState: .noBolus))
        #expect(!context.matches(pumpID: nil, activationDate: start, bolusState: .noBolus))
        #expect(!context.matches(pumpID: ObjectIdentifier(pump), activationDate: start.addingTimeInterval(1), bolusState: .noBolus))
    }

    @Test("A stale no-bolus cache is not silently accepted as a stopped bolus") func staleCacheIdentity() {
        let pump = NSObject()
        let context = BolusCancellationContext(pumpID: ObjectIdentifier(pump), activationDate: nil, bolusState: .noBolus)
        #expect(context.doseStart == nil)
        #expect(context.matches(pumpID: ObjectIdentifier(pump), activationDate: nil, bolusState: .noBolus))
        #expect(!context.matches(pumpID: ObjectIdentifier(pump), activationDate: nil, bolusState: .inProgress(dose(start: Date()))))
    }

    @Test("An explicit stop reaches the driver despite a cached no-bolus flag") func cachedNoBolusStillSends() async {
        let pump = NSObject()
        let context = BolusCancellationContext(pumpID: ObjectIdentifier(pump), activationDate: nil, bolusState: .noBolus)
        let coordinator = BolusCancellationCoordinator()
        var calls = 0
        let task = coordinator.request(mayCancel: {
            context.matches(pumpID: ObjectIdentifier(pump), activationDate: nil, bolusState: .noBolus)
        }, cancel: { calls += 1 }, shouldRetry: { _ in false })
        #expect(coordinator.state.value == .cancelling)
        _ = await task.value
        #expect(calls == 1)
        #expect(coordinator.state.value == .stopped)
    }
}
