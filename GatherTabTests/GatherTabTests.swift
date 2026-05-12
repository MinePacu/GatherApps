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

    func testActivationRaisesWindowsWhenAccessibilityIsTrusted() {
        let app = StubActivatableApplication(
            bundleIdentifier: "com.example.App",
            localizedName: "Example",
            processIdentifier: 1234,
            activationResult: false
        )
        let appProvider = StubApplicationProvider(app: app)
        let windowRaiser = StubWindowRaiser(isTrusted: true, raiseResult: true)
        let service = AppActivationService(
            applicationProvider: appProvider,
            windowRaiser: windowRaiser
        )

        let result = service.activate(bundleIdentifier: "com.example.App")

        XCTAssertEqual(result, .success(appName: "Example"))
        XCTAssertEqual(windowRaiser.raisedProcessIdentifiers, [1234])
        XCTAssertTrue(app.activationOptions.isEmpty)
    }

    func testLauncherGeneratorCreatesAppBundle() throws {
        let group = AppGroup(name: "Dev/Test")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherTabLauncherTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: destination)
        }

        let result = try LauncherAppGeneratorService()
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
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, result.bundleIdentifier)
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

private final class StubWindowRaiser: WindowRaising {
    let isTrusted: Bool
    let raiseResult: Bool
    private(set) var raisedProcessIdentifiers: [pid_t] = []

    init(isTrusted: Bool, raiseResult: Bool) {
        self.isTrusted = isTrusted
        self.raiseResult = raiseResult
    }

    func raiseWindows(for processIdentifier: pid_t) -> Bool {
        raisedProcessIdentifiers.append(processIdentifier)
        return raiseResult
    }
}
