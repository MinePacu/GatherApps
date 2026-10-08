import Foundation

/// Runs window-helper lifecycle operations one at a time, in the order they were requested.
/// Shared by every registration service instance, so a suspended operation (for example one
/// waiting for helpers to quit) never interleaves with another terminate/register/launch sequence.
/// An operation must not call `run(_:)` itself: it would wait for its own completion forever.
@MainActor
enum WindowHelperLifecycleSerializer {
    private static var tail: Task<Void, Never>?

    static func run<T: Sendable>(_ operation: @escaping @MainActor () async -> T) async -> T {
        let previous = tail
        let current = Task { @MainActor in
            _ = await previous?.value
            return await operation()
        }
        tail = Task { @MainActor in
            _ = await current.value
        }
        return await current.value
    }
}
