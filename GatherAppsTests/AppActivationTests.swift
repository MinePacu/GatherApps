import AppKit
import XCTest
@testable import GatherApps

@MainActor
final class AppActivationTests: XCTestCase {
    func testActivationUsesWindowHelperBeforeFallbackActivation() async {
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

        let result = await service.activate(bundleIdentifier: "com.example.App")

        XCTAssertEqual(result, .success(appName: "Example"))
        XCTAssertEqual(registrationService.ensureRegisteredCallCount, 1)
        XCTAssertEqual(helperClient.requestedBundleIdentifiers, ["com.example.App"])
        XCTAssertTrue(app.activationOptions.isEmpty)
    }

    func testActivationFallsBackWhenAccessibilityPermissionIsMissing() async {
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

        let result = await service.activate(bundleIdentifier: "com.example.App")

        XCTAssertEqual(result, .accessibilityPermissionMissing(appName: "Example"))
        XCTAssertEqual(app.activationOptions, [.activateAllWindows])
    }

    func testActivationFallsBackWhenHelperCannotRaiseWindows() async {
        let helperFailures: [WindowHelperActivationResult] = [
            .noWindowsFound(appName: "Example"),
            .raiseFailed(appName: "Example")
        ]

        for helperFailure in helperFailures {
            let app = StubActivatableApplication(
                bundleIdentifier: "com.example.App",
                localizedName: "Example",
                processIdentifier: 1234,
                activationResult: true
            )
            let service = AppActivationService(
                applicationProvider: StubApplicationProvider(app: app),
                helperRegistrationService: StubWindowHelperRegistrationService(result: .available),
                helperClient: StubWindowHelperClient(result: helperFailure)
            )

            let result = await service.activate(bundleIdentifier: "com.example.App")

            XCTAssertEqual(result, .success(appName: "Example"))
            XCTAssertEqual(app.activationOptions, [.activateAllWindows])
        }
    }

    func testActivationPreservesAccessibilityErrorWhenFallbackActivationFails() async {
        let app = StubActivatableApplication(
            bundleIdentifier: "com.example.App",
            localizedName: "Example",
            processIdentifier: 1234,
            activationResult: false
        )
        let service = AppActivationService(
            applicationProvider: StubApplicationProvider(app: app),
            helperRegistrationService: StubWindowHelperRegistrationService(result: .available),
            helperClient: StubWindowHelperClient(result: .accessibilityPermissionMissing)
        )

        let result = await service.activate(bundleIdentifier: "com.example.App")

        XCTAssertEqual(result, .accessibilityPermissionMissing(appName: "Example"))
        XCTAssertEqual(app.activationOptions, [.activateAllWindows])
    }

    func testActivationFallsBackToApplicationActivationWhenRegistrationIsUnavailable() async {
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

        let result = await service.activate(bundleIdentifier: "com.example.App")

        XCTAssertEqual(result, .success(appName: "Example"))
        XCTAssertTrue(helperClient.requestedBundleIdentifiers.isEmpty)
        XCTAssertEqual(app.activationOptions, [.activateAllWindows])
    }

    func testActivationPreservesRegistrationErrorWhenFallbackActivationFails() async {
        let app = StubActivatableApplication(
            bundleIdentifier: "com.example.App",
            localizedName: "Example",
            processIdentifier: 1234,
            activationResult: false
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

        let result = await service.activate(bundleIdentifier: "com.example.App")

        XCTAssertEqual(result, .helperUnavailable(reason: "Login item requires user approval."))
        XCTAssertTrue(helperClient.requestedBundleIdentifiers.isEmpty)
        XCTAssertEqual(app.activationOptions, [.activateAllWindows])
    }

    func testActivationFallsBackToApplicationActivationWhenHelperIsUnavailable() async {
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

        let result = await service.activate(bundleIdentifier: "com.example.App")

        XCTAssertEqual(result, .success(appName: "Example"))
        XCTAssertEqual(app.activationOptions, [.activateAllWindows])
    }

    func testActivationPreservesHelperErrorWhenFallbackActivationFails() async {
        let app = StubActivatableApplication(
            bundleIdentifier: "com.example.App",
            localizedName: "Example",
            processIdentifier: 1234,
            activationResult: false
        )
        let appProvider = StubApplicationProvider(app: app)
        let registrationService = StubWindowHelperRegistrationService(result: .available)
        let helperClient = StubWindowHelperClient(result: .helperUnavailable(reason: "missing helper"))
        let service = AppActivationService(
            applicationProvider: appProvider,
            helperRegistrationService: registrationService,
            helperClient: helperClient
        )

        let result = await service.activate(bundleIdentifier: "com.example.App")

        XCTAssertEqual(result, .helperUnavailable(reason: "missing helper"))
        XCTAssertEqual(app.activationOptions, [.activateAllWindows])
    }

    func testExecutableActivationActivatesRunningExecutableApplicationWithoutWindowHelper() async {
        let app = StubActivatableApplication(
            bundleIdentifier: nil,
            localizedName: "scrcpy",
            processIdentifier: 4321,
            activationResult: true
        )
        let appProvider = StubApplicationProvider(app: nil, executableApp: app)
        let registrationService = StubWindowHelperRegistrationService(result: .available)
        let helperClient = StubWindowHelperClient(result: .raised(appName: "unused", raisedWindowCount: 1))
        let service = AppActivationService(
            applicationProvider: appProvider,
            helperRegistrationService: registrationService,
            helperClient: helperClient
        )
        let target = GroupedApp(
            executablePath: "/opt/homebrew/bin/scrcpy",
            name: "scrcpy",
            appPath: nil
        )

        let result = await service.activate(target)

        XCTAssertEqual(result, .success(appName: "scrcpy"))
        XCTAssertEqual(appProvider.requestedExecutablePaths, ["/opt/homebrew/bin/scrcpy"])
        XCTAssertEqual(app.activationOptions, [.activateAllWindows])
        XCTAssertEqual(registrationService.ensureRegisteredCallCount, 0)
        XCTAssertTrue(helperClient.requestedBundleIdentifiers.isEmpty)
    }

    func testGroupActivationChecksHelperRegistrationOnce() async {
        let apps = makeRunningApps(count: 3, activationResult: false)
        let registrationService = StubWindowHelperRegistrationService(result: .available)
        let helperClient = StubWindowHelperClient(
            result: .raised(appName: "unused", raisedWindowCount: 1),
            resultsByBundleIdentifier: [
                "com.example.App0": .raised(appName: "Example 0", raisedWindowCount: 1),
                "com.example.App1": .raised(appName: "Example 1", raisedWindowCount: 1),
                "com.example.App2": .raised(appName: "Example 2", raisedWindowCount: 1)
            ]
        )
        let service = AppActivationService(
            applicationProvider: StubApplicationProvider(apps: apps),
            helperRegistrationService: registrationService,
            helperClient: helperClient
        )

        let results = await service.activateGroup(makeGroupedApps(count: 3))

        XCTAssertEqual(results, [
            .success(appName: "Example 0"),
            .success(appName: "Example 1"),
            .success(appName: "Example 2")
        ])
        XCTAssertEqual(registrationService.ensureRegisteredCallCount, 1)
        XCTAssertEqual(
            helperClient.requestedBundleIdentifiers,
            ["com.example.App0", "com.example.App1", "com.example.App2"]
        )
        XCTAssertTrue(apps.allSatisfy { $0.activationOptions.isEmpty })
    }

    func testGroupActivationSkipsHelperAfterHelperStopsResponding() async {
        let apps = makeRunningApps(count: 3, activationResult: true)
        let registrationService = StubWindowHelperRegistrationService(result: .available)
        let helperClient = StubWindowHelperClient(result: .helperUnavailable(reason: "timeout"))
        let service = AppActivationService(
            applicationProvider: StubApplicationProvider(apps: apps),
            helperRegistrationService: registrationService,
            helperClient: helperClient
        )

        let results = await service.activateGroup(makeGroupedApps(count: 3))

        XCTAssertEqual(results, [
            .success(appName: "Example 0"),
            .success(appName: "Example 1"),
            .success(appName: "Example 2")
        ])
        XCTAssertEqual(registrationService.ensureRegisteredCallCount, 1)
        XCTAssertEqual(helperClient.requestedBundleIdentifiers, ["com.example.App0"])
        for app in apps {
            XCTAssertEqual(app.activationOptions, [.activateAllWindows])
        }
    }

    func testGroupActivationReportsMissingAccessibilityForEachAppAfterFallback() async {
        let apps = makeRunningApps(count: 2, activationResult: true)
        let registrationService = StubWindowHelperRegistrationService(result: .available)
        let helperClient = StubWindowHelperClient(result: .accessibilityPermissionMissing)
        let service = AppActivationService(
            applicationProvider: StubApplicationProvider(apps: apps),
            helperRegistrationService: registrationService,
            helperClient: helperClient
        )

        let results = await service.activateGroup(makeGroupedApps(count: 2))

        XCTAssertEqual(results, [
            .accessibilityPermissionMissing(appName: "Example 0"),
            .accessibilityPermissionMissing(appName: "Example 1")
        ])
        XCTAssertEqual(registrationService.ensureRegisteredCallCount, 1)
        XCTAssertEqual(helperClient.requestedBundleIdentifiers, ["com.example.App0", "com.example.App1"])
        for app in apps {
            XCTAssertEqual(app.activationOptions, [.activateAllWindows])
        }
    }

    func testGroupActivationUsesFallbackForAllAppsWhenRegistrationIsUnavailable() async {
        let apps = makeRunningApps(count: 3, activationResult: true)
        let registrationService = StubWindowHelperRegistrationService(result: .unavailable(reason: "x"))
        let helperClient = StubWindowHelperClient(result: .raised(appName: "unused", raisedWindowCount: 1))
        let service = AppActivationService(
            applicationProvider: StubApplicationProvider(apps: apps),
            helperRegistrationService: registrationService,
            helperClient: helperClient
        )

        let results = await service.activateGroup(makeGroupedApps(count: 3))

        XCTAssertEqual(results, [
            .success(appName: "Example 0"),
            .success(appName: "Example 1"),
            .success(appName: "Example 2")
        ])
        XCTAssertEqual(registrationService.ensureRegisteredCallCount, 1)
        XCTAssertTrue(helperClient.requestedBundleIdentifiers.isEmpty)
        for app in apps {
            XCTAssertEqual(app.activationOptions, [.activateAllWindows])
        }
    }

    func testGroupActivationDoesNotCheckRegistrationWhenNoAppIsRunning() async {
        let registrationService = StubWindowHelperRegistrationService(result: .available)
        let helperClient = StubWindowHelperClient(result: .raised(appName: "unused", raisedWindowCount: 1))
        let service = AppActivationService(
            applicationProvider: StubApplicationProvider(apps: []),
            helperRegistrationService: registrationService,
            helperClient: helperClient
        )

        let results = await service.activateGroup(makeGroupedApps(count: 2))

        XCTAssertEqual(results, [
            .appNotRunning(bundleIdentifier: "com.example.App0"),
            .appNotRunning(bundleIdentifier: "com.example.App1")
        ])
        XCTAssertEqual(registrationService.ensureRegisteredCallCount, 0)
        XCTAssertTrue(helperClient.requestedBundleIdentifiers.isEmpty)
    }

    func testSingleActivationStillChecksRegistrationEachCall() async {
        let apps = makeRunningApps(count: 1, activationResult: false)
        let registrationService = StubWindowHelperRegistrationService(result: .available)
        let helperClient = StubWindowHelperClient(result: .raised(appName: "Example 0", raisedWindowCount: 1))
        let service = AppActivationService(
            applicationProvider: StubApplicationProvider(apps: apps),
            helperRegistrationService: registrationService,
            helperClient: helperClient
        )

        _ = await service.activate(bundleIdentifier: "com.example.App0")
        _ = await service.activate(bundleIdentifier: "com.example.App0")

        XCTAssertEqual(registrationService.ensureRegisteredCallCount, 2)
        XCTAssertEqual(helperClient.requestedBundleIdentifiers, ["com.example.App0", "com.example.App0"])
    }

    private func makeRunningApps(count: Int, activationResult: Bool) -> [StubActivatableApplication] {
        (0..<count).map { index in
            StubActivatableApplication(
                bundleIdentifier: "com.example.App\(index)",
                localizedName: "Example \(index)",
                processIdentifier: pid_t(1000 + index),
                activationResult: activationResult
            )
        }
    }

    private func makeGroupedApps(count: Int) -> [GroupedApp] {
        (0..<count).map { index in
            GroupedApp(bundleIdentifier: "com.example.App\(index)", name: "Example \(index)", appPath: nil)
        }
    }
}

private final class StubActivatableApplication: ActivatableApplication {
    let bundleIdentifier: String?
    let localizedName: String?
    let processIdentifier: pid_t
    private(set) var isActive = false
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
        isActive = activationResult
        return activationResult
    }
}

private final class StubApplicationProvider: ApplicationProviding {
    let apps: [StubActivatableApplication]
    let executableApp: StubActivatableApplication?
    private(set) var requestedExecutablePaths: [String] = []

    init(app: StubActivatableApplication?, executableApp: StubActivatableApplication? = nil) {
        self.apps = app.map { [$0] } ?? []
        self.executableApp = executableApp
    }

    init(apps: [StubActivatableApplication]) {
        self.apps = apps
        self.executableApp = nil
    }

    func runningApplication(bundleIdentifier: String) -> ActivatableApplication? {
        apps.first { $0.bundleIdentifier == bundleIdentifier }
    }

    func runningApplication(executablePath: String) -> ActivatableApplication? {
        requestedExecutablePaths.append(executablePath)
        return executableApp
    }
}

private final class StubWindowHelperRegistrationService: WindowHelperRegistrationProviding {
    let result: WindowHelperRegistrationResult
    private(set) var ensureRegisteredCallCount = 0

    init(result: WindowHelperRegistrationResult) {
        self.result = result
    }

    func ensureRegistered() async -> WindowHelperRegistrationResult {
        ensureRegisteredCallCount += 1
        return result
    }
}

private final class StubWindowHelperClient: WindowHelperClient {
    let result: WindowHelperActivationResult
    let resultsByBundleIdentifier: [String: WindowHelperActivationResult]
    private(set) var requestedBundleIdentifiers: [String] = []

    init(
        result: WindowHelperActivationResult,
        resultsByBundleIdentifier: [String: WindowHelperActivationResult] = [:]
    ) {
        self.result = result
        self.resultsByBundleIdentifier = resultsByBundleIdentifier
    }

    func raiseWindows(bundleIdentifier: String) async -> WindowHelperActivationResult {
        requestedBundleIdentifiers.append(bundleIdentifier)
        return resultsByBundleIdentifier[bundleIdentifier] ?? result
    }
}

final class StubAppActivationService: AppActivationProviding {
    private(set) var requestedApps: [GroupedApp] = []
    private(set) var requestedBundleIdentifiers: [String] = []

    func activate(_ app: GroupedApp) async -> ActivationResult {
        requestedApps.append(app)
        return .success(appName: app.name)
    }

    func activate(bundleIdentifier: String) async -> ActivationResult {
        requestedBundleIdentifiers.append(bundleIdentifier)
        return .success(appName: bundleIdentifier)
    }
}
