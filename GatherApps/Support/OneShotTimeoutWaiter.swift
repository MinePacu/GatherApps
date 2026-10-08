import Foundation

/// Suspends the main actor until `finish(_:)` delivers a value or the timeout elapses.
/// Whichever comes first resumes the waiter; later deliveries are ignored.
@MainActor
final class OneShotTimeoutWaiter<Value> {
    private enum State {
        case pending(CheckedContinuation<Value, Never>?)
        case finished(Value)
    }

    private var state: State = .pending(nil)

    func finish(_ value: Value) {
        guard case .pending(let continuation) = state else { return }
        state = .finished(value)
        continuation?.resume(returning: value)
    }

    func wait(timeout: TimeInterval, timeoutValue: Value) async -> Value {
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            finish(timeoutValue)
        }
        defer { timeoutTask.cancel() }

        return await withCheckedContinuation { continuation in
            switch state {
            case .pending:
                state = .pending(continuation)
            case .finished(let value):
                continuation.resume(returning: value)
            }
        }
    }
}
