import AppKit
import XCTest
@testable import GatherApps

@MainActor
final class AppActivationTests: XCTestCase {
    func testActivationUsesWindowHelperBeforeFallbackActivation() {
        let app = StubActivatableApplication(
            bundleIdentifier: "com.example.App",
            localizedName: "Example",
            processIdentifier: 1234,
            activationResult: false
        )
        let appProvider = StubApplicationProvider(app: app)
        let registrationService = StubWindowHelperRegistrationService(result: .available)
        let helperClient = StubWindowHelperClient(result: .raised(appName: "Example", raisedWindowCount: 1))
        let service = AppActivationService(
            applicationProvider: appProvider,
            helperRegistrationService: registrationService,
            helperClient: helperClient
        )

        let result = service.activate(bundleIdentifier: "com.example.App")

        XCTAssertEqual(result, .success(appName: "Example"))
        XCTAssertEqual(registrationService.ensureRegisteredCallCount, 1)
        XCTAssertEqual(helperClient.requestedBundleIdentifiers, ["com.example.App"])
        XCTAssertTrue(app.activationOptions.isEmpty)
    }

    func testActivationReportsAccessibilityPermissionMissingFromHelper() {
        let app = StubActivatableApplication(
            bundleIdentifier: "com.example.App",
            localizedName: "Example",
            processIdentifier: 1234,
            activationResult: true
        )
        let appProvider = StubApplicationProvider(app: app)
        let registrationService = StubWindowHelperRegistrationService(result: .available)
        let helperClient = StubWindowHelperClient(result: .accessibilityPermissionMissing)
        let service = AppActivationService(
            applicationProvider: appProvider,
            helperRegistrationService: registrationService,
            helperClient: helperClient
        )

        let result = service.activate(bundleIdentifier: "com.example.App")

        XCTAssertEqual(result, .accessibilityPermissionMissing(appName: "Example"))
        XCTAssertTrue(app.activationOptions.isEmpty)
    }

    func testActivationReportsHelperUnavailableWhenLoginItemNeedsApproval() {
        let app = StubActivatableApplication(
            bundleIdentifier: "com.example.App",
            localizedName: "Example",
            processIdentifier: 1234,
            activationResult: true
        )
        let appProvider = StubApplicationProvider(app: app)
        let registrationService = StubWindowHelperRegistrationService(
            result: .unavailable(reason: "Login item requires user approval.")
        )
        let helperClient = StubWindowHelperClient(result: .raised(appName: "Example", raisedWindowCount: 1))
        let service = AppActivationService(
            applicationProvider: appProvider,
            helperRegistrationService: registrationService,
            helperClient: helperClient
        )

        let result = service.activate(bundleIdentifier: "com.example.App")

        XCTAssertEqual(result, .helperUnavailable(reason: "Login item requires user approval."))
        XCTAssertTrue(helperClient.requestedBundleIdentifiers.isEmpty)
        XCTAssertTrue(app.activationOptions.isEmpty)
    }

    func testActivationFallsBackToApplicationActivationWhenHelperIsUnavailable() {
        let app = StubActivatableApplication(
            bundleIdentifier: "com.example.App",
            localizedName: "Example",
            processIdentifier: 1234,
            activationResult: true
        )
        let appProvider = StubApplicationProvider(app: app)
        let registrationService = StubWindowHelperRegistrationService(result: .available)
        let helperClient = StubWindowHelperClient(result: .helperUnavailable(reason: "missing helper"))
        let service = AppActivationService(
            applicationProvider: appProvider,
            helperRegistrationService: registrationService,
            helperClient: helperClient
        )

        let result = service.activate(bundleIdentifier: "com.example.App")

        XCTAssertEqual(result, .success(appName: "Example"))
        XCTAssertEqual(app.activationOptions, [.activateAllWindows])
    }

}

private final class StubActivatableApplication: ActivatableApplication {
    let bundleIdentifier: String?
    let localizedName: String?
    let processIdentifier: pid_t
    private let activationResult: Bool
    private(set) var activationOptions: [NSApplication.ActivationOptions] = []

    init(
        bundleIdentifier: String?,
        localizedName: String?,
        processIdentifier: pid_t,
        activationResult: Bool
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.processIdentifier = processIdentifier
        self.activationResult = activationResult
    }

    func activate(options: NSApplication.ActivationOptions) -> Bool {
        activationOptions.append(options)
        return activationResult
    }
}

private struct StubApplicationProvider: ApplicationProviding {
    let app: StubActivatableApplication?

    func runningApplication(bundleIdentifier: String) -> ActivatableApplication? {
        app?.bundleIdentifier == bundleIdentifier ? app : nil
    }
}

private final class StubWindowHelperRegistrationService: WindowHelperRegistrationProviding {
    let result: WindowHelperRegistrationResult
    private(set) var ensureRegisteredCallCount = 0

    init(result: WindowHelperRegistrationResult) {
        self.result = result
    }

    func ensureRegistered() -> WindowHelperRegistrationResult {
        ensureRegisteredCallCount += 1
        return result
    }
}

private final class StubWindowHelperClient: WindowHelperClient {
    let result: WindowHelperActivationResult
    private(set) var requestedBundleIdentifiers: [String] = []

    init(result: WindowHelperActivationResult) {
        self.result = result
    }

    func raiseWindows(bundleIdentifier: String) -> WindowHelperActivationResult {
        requestedBundleIdentifiers.append(bundleIdentifier)
        return result
    }
}

final class StubAppActivationService: AppActivationProviding {
    private(set) var requestedBundleIdentifiers: [String] = []

    func activate(bundleIdentifier: String) -> ActivationResult {
        requestedBundleIdentifiers.append(bundleIdentifier)
        return .success(appName: bundleIdentifier)
    }
}
