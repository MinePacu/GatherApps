import Foundation
import ServiceManagement
import XCTest
@testable import GatherApps

@MainActor
final class WindowHelperLifecycleSerializationTests: XCTestCase {
    func testLifecycleOperationsOfDifferentServicesDoNotInterleave() async {
        let helperURL = Bundle.main.bundleURL
        let gate = LifecycleGate()
        let recorder = SerializationCallRecorder()

        // A has nothing registered and fails to register, so it falls back to a launch that suspends.
        let loginItemA = SerializationStubLoginItemService(name: "A", status: .notRegistered, recorder: recorder)
        loginItemA.registerError = SerializationStubError.registrationFailed
        let processesA = SerializationStubProcessController(
            name: "A",
            runningHelpers: [],
            helperURL: helperURL,
            recorder: recorder,
            launchSuspension: { await gate.pass() }
        )
        let serviceA = makeService(loginItem: loginItemA, processes: processesA, helperURL: helperURL)

        // B restarts a current, enabled helper: it terminates it and launches it again.
        let loginItemB = SerializationStubLoginItemService(name: "B", status: .enabled, recorder: recorder)
        let processesB = SerializationStubProcessController(
            name: "B",
            runningHelpers: [WindowHelperProcess(processIdentifier: 40, bundleURL: helperURL)],
            helperURL: helperURL,
            recorder: recorder,
            launchSuspension: nil
        )
        let serviceB = makeService(loginItem: loginItemB, processes: processesB, helperURL: helperURL)

        let first = Task { await serviceA.ensureRegistered() }
        // A is now suspended inside its helper launch.
        await gate.waitForArrival()
        let second = Task { await serviceB.restart() }
        await runPendingMainActorWork()

        XCTAssertEqual(recorder.calls, ["A terminate:", "A register", "A launch start"])

        gate.open()
        let firstResult = await first.value
        let secondResult = await second.value

        XCTAssertEqual(firstResult, .available)
        XCTAssertEqual(secondResult, .available)
        XCTAssertEqual(recorder.calls, [
            "A terminate:", "A register", "A launch start", "A launch end",
            "B terminate:40", "B launch start", "B launch end"
        ])
    }

    func testSerializerStartsNextOperationOnlyAfterPreviousOneFinishes() async {
        let gate = LifecycleGate()
        let recorder = SerializationCallRecorder()

        let first = Task {
            await WindowHelperLifecycleSerializer.run { () async -> Int in
                recorder.calls.append("first start")
                await gate.pass()
                recorder.calls.append("first end")
                return 1
            }
        }
        await gate.waitForArrival()
        let second = Task {
            await WindowHelperLifecycleSerializer.run { () async -> String in
                recorder.calls.append("second start")
                return "second"
            }
        }
        await runPendingMainActorWork()

        XCTAssertEqual(recorder.calls, ["first start"])

        gate.open()
        let firstValue = await first.value
        let secondValue = await second.value

        XCTAssertEqual(firstValue, 1)
        XCTAssertEqual(secondValue, "second")
        XCTAssertEqual(recorder.calls, ["first start", "first end", "second start"])
    }

    /// Lets work already queued on the main actor run up to its next suspension point.
    private func runPendingMainActorWork() async {
        for _ in 0..<5 {
            let marker = Task {}
            await marker.value
        }
    }

    private func makeService(
        loginItem: SerializationStubLoginItemService,
        processes: SerializationStubProcessController,
        helperURL: URL
    ) -> LoginItemWindowHelperRegistrationService {
        LoginItemWindowHelperRegistrationService(
            loginItemService: loginItem,
            processController: processes,
            helperURL: helperURL,
            startupGracePeriod: 0,
            transitionTimeout: 0
        )
    }
}

@MainActor
private final class SerializationCallRecorder {
    var calls: [String] = []
}

/// Holds every caller of `pass()` until the test opens it, and lets the test wait for the first caller.
@MainActor
private final class LifecycleGate {
    private var isOpen = false
    private var hasArrival = false
    private var heldCallers: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        hasArrival = true
        arrivalWaiters.forEach { $0.resume() }
        arrivalWaiters.removeAll()
        guard !isOpen else { return }
        await withCheckedContinuation { heldCallers.append($0) }
    }

    func waitForArrival() async {
        guard !hasArrival else { return }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    func open() {
        isOpen = true
        heldCallers.forEach { $0.resume() }
        heldCallers.removeAll()
    }
}

@MainActor
private final class SerializationStubLoginItemService: WindowHelperLoginItemServicing {
    var status: SMAppService.Status
    var registerError: Error?
    private let name: String
    private let recorder: SerializationCallRecorder

    init(name: String, status: SMAppService.Status, recorder: SerializationCallRecorder) {
        self.name = name
        self.status = status
        self.recorder = recorder
    }

    func register() throws {
        recorder.calls.append("\(name) register")
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        recorder.calls.append("\(name) unregister")
        status = .notRegistered
    }
}

@MainActor
private final class SerializationStubProcessController: WindowHelperProcessControlling {
    var runningHelpers: [WindowHelperProcess]
    private let name: String
    private let helperURL: URL
    private let recorder: SerializationCallRecorder
    private let launchSuspension: (@MainActor () async -> Void)?

    init(
        name: String,
        runningHelpers: [WindowHelperProcess],
        helperURL: URL,
        recorder: SerializationCallRecorder,
        launchSuspension: (@MainActor () async -> Void)?
    ) {
        self.name = name
        self.runningHelpers = runningHelpers
        self.helperURL = helperURL
        self.recorder = recorder
        self.launchSuspension = launchSuspension
    }

    func terminate(processIdentifiers: [pid_t]) {
        let identifiers = Set(processIdentifiers)
        recorder.calls.append("\(name) terminate:\(processIdentifiers.map(String.init).joined(separator: ","))")
        runningHelpers.removeAll { identifiers.contains($0.processIdentifier) }
    }

    func launchHelper(at url: URL) async -> Error? {
        recorder.calls.append("\(name) launch start")
        await launchSuspension?()
        recorder.calls.append("\(name) launch end")
        runningHelpers = [WindowHelperProcess(processIdentifier: 99, bundleURL: helperURL)]
        return nil
    }
}

private enum SerializationStubError: LocalizedError {
    case registrationFailed

    var errorDescription: String? {
        "registration failed"
    }
}
