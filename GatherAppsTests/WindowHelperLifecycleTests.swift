import Foundation
import ServiceManagement
import XCTest
@testable import GatherApps

@MainActor
final class WindowHelperLifecycleTests: XCTestCase {
    func testEnabledCurrentHelperDoesNotChangeRegistration() {
        let helperURL = Bundle.main.bundleURL
        let recorder = WindowHelperCallRecorder()
        let loginItem = StubWindowHelperLoginItemService(status: .enabled, recorder: recorder)
        let processes = StubWindowHelperProcessController(
            runningHelpers: [WindowHelperProcess(processIdentifier: 10, bundleURL: helperURL)],
            helperURL: helperURL,
            recorder: recorder
        )
        let service = makeService(loginItem: loginItem, processes: processes, helperURL: helperURL)

        XCTAssertEqual(service.ensureRegistered(), .available)
        XCTAssertTrue(recorder.calls.isEmpty)
    }

    func testEnabledStaleHelperIsTerminatedAndRegistrationIsReplaced() {
        let helperURL = Bundle.main.bundleURL
        let staleURL = helperURL.deletingLastPathComponent().appendingPathComponent("StaleHelper.app")
        let recorder = WindowHelperCallRecorder()
        let loginItem = StubWindowHelperLoginItemService(status: .enabled, recorder: recorder)
        let processes = StubWindowHelperProcessController(
            runningHelpers: [WindowHelperProcess(processIdentifier: 20, bundleURL: staleURL)],
            helperURL: helperURL,
            recorder: recorder
        )
        loginItem.onRegister = {
            processes.runningHelpers = [WindowHelperProcess(processIdentifier: 21, bundleURL: helperURL)]
        }
        let service = makeService(loginItem: loginItem, processes: processes, helperURL: helperURL)

        XCTAssertEqual(service.ensureRegistered(), .available)
        XCTAssertEqual(recorder.calls, ["terminate:20", "unregister", "register"])
    }

    func testEnabledWithoutRunningHelperReplacesRegistrationAfterGracePeriod() {
        let helperURL = Bundle.main.bundleURL
        let recorder = WindowHelperCallRecorder()
        let loginItem = StubWindowHelperLoginItemService(status: .enabled, recorder: recorder)
        let processes = StubWindowHelperProcessController(
            runningHelpers: [],
            helperURL: helperURL,
            recorder: recorder
        )
        loginItem.onRegister = {
            processes.runningHelpers = [WindowHelperProcess(processIdentifier: 30, bundleURL: helperURL)]
        }
        let service = makeService(loginItem: loginItem, processes: processes, helperURL: helperURL)

        XCTAssertEqual(service.ensureRegistered(), .available)
        XCTAssertEqual(recorder.calls, ["terminate:", "unregister", "register"])
    }

    func testRegistrationFailureFallsBackToDirectCurrentHelperLaunch() {
        let helperURL = Bundle.main.bundleURL
        let recorder = WindowHelperCallRecorder()
        let loginItem = StubWindowHelperLoginItemService(status: .notRegistered, recorder: recorder)
        loginItem.registerError = StubWindowHelperError.registrationFailed
        let processes = StubWindowHelperProcessController(
            runningHelpers: [],
            helperURL: helperURL,
            recorder: recorder
        )
        let service = makeService(loginItem: loginItem, processes: processes, helperURL: helperURL)

        XCTAssertEqual(service.ensureRegistered(), .available)
        XCTAssertEqual(recorder.calls, ["terminate:", "register", "launch:\(helperURL.path)"])
    }

    func testRegistrationAndDirectLaunchFailureReturnsUnavailable() {
        let helperURL = Bundle.main.bundleURL
        let recorder = WindowHelperCallRecorder()
        let loginItem = StubWindowHelperLoginItemService(status: .notRegistered, recorder: recorder)
        loginItem.registerError = StubWindowHelperError.registrationFailed
        let processes = StubWindowHelperProcessController(
            runningHelpers: [],
            helperURL: helperURL,
            recorder: recorder
        )
        processes.launchError = StubWindowHelperError.launchFailed
        let service = makeService(loginItem: loginItem, processes: processes, helperURL: helperURL)

        guard case .unavailable(let reason) = service.ensureRegistered() else {
            return XCTFail("Expected the helper to be unavailable")
        }
        XCTAssertTrue(reason.contains("launch failed"))
    }

    func testRequiresApprovalDoesNotChangeRegistration() {
        let helperURL = Bundle.main.bundleURL
        let recorder = WindowHelperCallRecorder()
        let loginItem = StubWindowHelperLoginItemService(status: .requiresApproval, recorder: recorder)
        let processes = StubWindowHelperProcessController(
            runningHelpers: [],
            helperURL: helperURL,
            recorder: recorder
        )
        let service = makeService(loginItem: loginItem, processes: processes, helperURL: helperURL)

        XCTAssertEqual(service.ensureRegistered(), .available)
        XCTAssertEqual(recorder.calls, ["launch:\(helperURL.path)"])
        XCTAssertFalse(recorder.calls.contains("register"))
        XCTAssertFalse(recorder.calls.contains("unregister"))
    }

    func testRestartOfCurrentEnabledHelperKeepsRegistrationAndLaunchesCurrentBundle() {
        let helperURL = Bundle.main.bundleURL
        let recorder = WindowHelperCallRecorder()
        let loginItem = StubWindowHelperLoginItemService(status: .enabled, recorder: recorder)
        let processes = StubWindowHelperProcessController(
            runningHelpers: [WindowHelperProcess(processIdentifier: 40, bundleURL: helperURL)],
            helperURL: helperURL,
            recorder: recorder
        )
        let service = makeService(loginItem: loginItem, processes: processes, helperURL: helperURL)

        XCTAssertEqual(service.restart(), .available)
        XCTAssertEqual(recorder.calls, ["terminate:40", "launch:\(helperURL.path)"])
    }

    func testCanonicalURLTreatsSymbolicLinkAsSameBundle() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleURL = temporaryDirectory.appendingPathComponent("Helper.app", isDirectory: true)
        let symbolicLinkURL = temporaryDirectory.appendingPathComponent("HelperLink.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symbolicLinkURL, withDestinationURL: bundleURL)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        XCTAssertTrue(WindowHelperBundleDiagnostics.urlsReferToSameBundle(bundleURL, symbolicLinkURL))
    }

    private func makeService(
        loginItem: StubWindowHelperLoginItemService,
        processes: StubWindowHelperProcessController,
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

private final class WindowHelperCallRecorder {
    var calls: [String] = []
}

private final class StubWindowHelperLoginItemService: WindowHelperLoginItemServicing {
    var status: SMAppService.Status
    var registerError: Error?
    var unregisterError: Error?
    var onRegister: (() -> Void)?
    private let recorder: WindowHelperCallRecorder

    init(status: SMAppService.Status, recorder: WindowHelperCallRecorder) {
        self.status = status
        self.recorder = recorder
    }

    func register() throws {
        recorder.calls.append("register")
        if let registerError { throw registerError }
        status = .enabled
        onRegister?()
    }

    func unregister() throws {
        recorder.calls.append("unregister")
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }
}

private final class StubWindowHelperProcessController: WindowHelperProcessControlling {
    var runningHelpers: [WindowHelperProcess]
    var launchError: Error?
    private let helperURL: URL
    private let recorder: WindowHelperCallRecorder

    init(
        runningHelpers: [WindowHelperProcess],
        helperURL: URL,
        recorder: WindowHelperCallRecorder
    ) {
        self.runningHelpers = runningHelpers
        self.helperURL = helperURL
        self.recorder = recorder
    }

    func terminate(processIdentifiers: [pid_t]) {
        let identifiers = Set(processIdentifiers)
        recorder.calls.append("terminate:\(processIdentifiers.map(String.init).joined(separator: ","))")
        runningHelpers.removeAll { identifiers.contains($0.processIdentifier) }
    }

    func launchHelper(at url: URL) -> Error? {
        recorder.calls.append("launch:\(url.path)")
        if let launchError { return launchError }
        runningHelpers = [WindowHelperProcess(processIdentifier: 99, bundleURL: helperURL)]
        return nil
    }
}

private enum StubWindowHelperError: LocalizedError {
    case registrationFailed
    case launchFailed

    var errorDescription: String? {
        switch self {
        case .registrationFailed:
            "registration failed"
        case .launchFailed:
            "launch failed"
        }
    }
}
