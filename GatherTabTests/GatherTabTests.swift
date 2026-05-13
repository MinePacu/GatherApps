import AppKit
import XCTest
@testable import GatherTab

@MainActor
final class GatherTabTests: XCTestCase {
    func testActivationURLRoundTripsGroupID() {
        let groupID = UUID()
        let url = GatherTabURLScheme.activationURL(for: groupID)

        XCTAssertEqual(url.absoluteString, "gathertab://activate-group/\(groupID.uuidString)")
        XCTAssertEqual(GatherTabURLScheme.groupID(from: url), groupID)
    }

    func testActivationURLCanRequestBackgroundActivation() {
        let groupID = UUID()
        let url = GatherTabURLScheme.activationURL(for: groupID, showsGatherTabWindow: false)

        XCTAssertEqual(url.absoluteString, "gathertab://activate-group/\(groupID.uuidString)?showWindow=false")
        XCTAssertEqual(GatherTabURLScheme.groupID(from: url), groupID)
        XCTAssertFalse(GatherTabURLScheme.showsGatherTabWindow(from: url))
    }

    func testPlainActivationURLDefaultsToShowingGatherTabWindow() {
        let groupID = UUID()
        let url = GatherTabURLScheme.activationURL(for: groupID)

        XCTAssertTrue(GatherTabURLScheme.showsGatherTabWindow(from: url))
    }

    func testWindowHelperIdentifierUsesMainAppBundlePrefix() {
        XCTAssertEqual(WindowHelperConfiguration.loginItemIdentifier, "com.minepacu.GatherTab.WindowHelper")
    }

    func testRunningAppServiceReturnsOneAppPerBundleIdentifier() {
        let duplicateBundleID = "com.apple.quicklook.QuickLookUIService"
        let apps = [
            RunningAppInfo(
                bundleIdentifier: duplicateBundleID,
                name: "Quick Look",
                appURL: URL(fileURLWithPath: "/System/Library/CoreServices/QuickLookUIService.app")
            ),
            RunningAppInfo(
                bundleIdentifier: "com.apple.TextEdit",
                name: "TextEdit",
                appURL: URL(fileURLWithPath: "/System/Applications/TextEdit.app")
            ),
            RunningAppInfo(
                bundleIdentifier: duplicateBundleID,
                name: "Quick Look",
                appURL: URL(fileURLWithPath: "/System/Library/CoreServices/QuickLookUIService.app")
            )
        ]

        let uniqueApps = RunningAppService.uniqueApps(apps)

        XCTAssertEqual(uniqueApps.map(\.bundleIdentifier), [
            duplicateBundleID,
            "com.apple.TextEdit"
        ])
    }

    func testGroupIconGenerationUsesNewFileNameForRegeneratedIcon() throws {
        let group = AppGroup(name: "Dev")
        let iconService = GroupIconService()

        let firstFileName = try iconService.generateIcon(for: group)
        let secondFileName = try iconService.generateIcon(for: group)

        defer {
            if let firstURL = iconService.iconURL(for: firstFileName) {
                try? FileManager.default.removeItem(at: firstURL)
            }
            if let secondURL = iconService.iconURL(for: secondFileName) {
                try? FileManager.default.removeItem(at: secondURL)
            }
        }

        XCTAssertNotEqual(firstFileName, secondFileName)
    }

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

    func testLauncherGeneratorCreatesAppBundle() throws {
        let group = AppGroup(name: "Dev/Test")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherTabLauncherTests-\(UUID().uuidString)", isDirectory: true)
        let runtimeExecutableURL = destination
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("GatherTabLauncherRuntime")
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: runtimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "runtime executable".write(to: runtimeExecutableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeExecutableURL.path)

        let result = try LauncherAppGeneratorService(launcherRuntimeExecutableURL: runtimeExecutableURL)
            .generateLauncher(for: group, destinationDirectory: destination)

        let infoPlistURL = result.appURL.appendingPathComponent("Contents/Info.plist")
        let executableURL = result.appURL.appendingPathComponent("Contents/MacOS/GatherTabLauncher")
        let iconURL = result.appURL.appendingPathComponent("Contents/Resources/GroupIcon.icns")

        XCTAssertTrue(FileManager.default.fileExists(atPath: infoPlistURL.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executableURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path))

        let infoData = try Data(contentsOf: infoPlistURL)
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(info["CFBundleName"] as? String, "GatherTab - Dev-Test")
        XCTAssertEqual(info["GatherTabGroupID"] as? String, group.id.uuidString)
        XCTAssertEqual(info["GatherTabShowsGatherTabWindow"] as? Bool, false)
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, result.bundleIdentifier)
        XCTAssertNil(info["LSUIElement"])
        XCTAssertNil(info["LSBackgroundOnly"])
    }

    func testLauncherGeneratorDefaultsToUserApplicationsLaunchersDirectory() throws {
        let runtimeExecutableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherTabLauncherDefaultDestinationRuntime-\(UUID().uuidString)")
        try "runtime executable".write(to: runtimeExecutableURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: runtimeExecutableURL)
        }

        let generator = LauncherAppGeneratorService(launcherRuntimeExecutableURL: runtimeExecutableURL)

        XCTAssertEqual(
            try generator.defaultDestinationDirectory(),
            try AppSupportPaths.userLaunchersDirectory
        )
    }

    func testLauncherGeneratorCopiesRuntimeExecutableForCommandTabVisibility() throws {
        let group = AppGroup(name: "Command Tab")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherTabLauncherRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        let runtimeExecutableURL = destination
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("GatherTabLauncherRuntime")
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: runtimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let runtimeContents = "compiled foreground runtime"
        try runtimeContents.write(to: runtimeExecutableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeExecutableURL.path)

        let result = try LauncherAppGeneratorService(launcherRuntimeExecutableURL: runtimeExecutableURL)
            .generateLauncher(for: group, destinationDirectory: destination)

        let executableURL = result.appURL.appendingPathComponent("Contents/MacOS/GatherTabLauncher")
        let generatedContents = try String(contentsOf: executableURL, encoding: .utf8)

        XCTAssertEqual(generatedContents, runtimeContents)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executableURL.path))
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
