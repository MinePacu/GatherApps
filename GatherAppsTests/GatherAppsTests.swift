import AppKit
import XCTest
@testable import GatherApps

@MainActor
final class GatherAppsTests: XCTestCase {
    func testSidebarDoesNotDefineDedicatedDeleteToolbarButton() throws {
        let projectRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sidebarURL = projectRootURL
            .appendingPathComponent("GatherApps", isDirectory: true)
            .appendingPathComponent("Views", isDirectory: true)
            .appendingPathComponent("SidebarView.swift")
        let sidebarSource = try String(contentsOf: sidebarURL, encoding: .utf8)

        XCTAssertFalse(sidebarSource.contains("deleteSelectedGroup"))
        XCTAssertFalse(sidebarSource.contains("Label(\"sidebar.deleteGroup\""))
    }

    func testDeletingSelectedGroupSelectsFirstRemainingGroup() {
        let deletedID = UUID()
        let nextID = UUID()
        let otherID = UUID()

        let nextSelection = ContentSelection.selection(
            afterDeleting: deletedID,
            currentSelection: deletedID,
            remainingGroupIDs: [nextID, otherID]
        )

        XCTAssertEqual(nextSelection, nextID)
    }

    func testDeletingUnselectedGroupPreservesCurrentSelection() {
        let deletedID = UUID()
        let selectedID = UUID()
        let otherID = UUID()

        let nextSelection = ContentSelection.selection(
            afterDeleting: deletedID,
            currentSelection: selectedID,
            remainingGroupIDs: [selectedID, otherID]
        )

        XCTAssertEqual(nextSelection, selectedID)
    }

    func testLocalizableStringsHaveMatchingKeysForSupportedLanguages() throws {
        let projectRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceURL = projectRootURL.appendingPathComponent("GatherApps", isDirectory: true)
        let supportedLanguages = ["en", "ko", "ja"]

        let keysByLanguage = try Dictionary(
            uniqueKeysWithValues: supportedLanguages.map { language in
                let stringsURL = appSourceURL
                    .appendingPathComponent("\(language).lproj", isDirectory: true)
                    .appendingPathComponent("Localizable.strings")
                let keys = try Self.localizationKeys(at: stringsURL)
                return (language, keys)
            }
        )

        let englishKeys = try XCTUnwrap(keysByLanguage["en"])
        for language in supportedLanguages where language != "en" {
            XCTAssertEqual(keysByLanguage[language], englishKeys, "\(language) localization keys should match English")
        }
    }

    func testActivationURLRoundTripsGroupID() {
        let groupID = UUID()
        let url = GatherAppsURLScheme.activationURL(for: groupID)

        XCTAssertEqual(url.absoluteString, "gatherapps://activate-group/\(groupID.uuidString)")
        XCTAssertEqual(GatherAppsURLScheme.groupID(from: url), groupID)
    }

    func testActivationURLCanRequestBackgroundActivation() {
        let groupID = UUID()
        let url = GatherAppsURLScheme.activationURL(for: groupID, showsGatherAppsWindow: false)

        XCTAssertEqual(url.absoluteString, "gatherapps://activate-group/\(groupID.uuidString)?showWindow=false")
        XCTAssertEqual(GatherAppsURLScheme.groupID(from: url), groupID)
        XCTAssertFalse(GatherAppsURLScheme.showsGatherAppsWindow(from: url))
    }

    func testPlainActivationURLDefaultsToShowingGatherAppsWindow() {
        let groupID = UUID()
        let url = GatherAppsURLScheme.activationURL(for: groupID)

        XCTAssertTrue(GatherAppsURLScheme.showsGatherAppsWindow(from: url))
    }

    func testAppGroupDecodesLegacyLauncherWindowPolicyKey() throws {
        let groupID = UUID()
        let json = """
        {
          "id": "\(groupID.uuidString)",
          "name": "Legacy",
          "apps": [],
          "launcherShowsGatherTabWindow": true
        }
        """

        let group = try JSONDecoder().decode(AppGroup.self, from: Data(json.utf8))

        XCTAssertTrue(group.launcherShowsGatherAppsWindow)
    }

    func testUpdateVersionComparisonDetectsNewerSemanticVersion() {
        XCTAssertTrue(UpdateVersion("1.2.0").isNewer(than: UpdateVersion("1.1.9")))
        XCTAssertTrue(UpdateVersion("2.0").isNewer(than: UpdateVersion("1.9.9")))
        XCTAssertFalse(UpdateVersion("1.2.0").isNewer(than: UpdateVersion("1.2")))
        XCTAssertFalse(UpdateVersion("1.2.0").isNewer(than: UpdateVersion("1.2.1")))
    }

    func testUpdateMetadataParsesAppcastItem() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>GatherApps Updates</title>
            <item>
              <title>Version 1.2.0</title>
              <sparkle:shortVersionString>1.2.0</sparkle:shortVersionString>
              <sparkle:version>42</sparkle:version>
              <description><![CDATA[<p>Improved launcher refresh.</p>]]></description>
            </item>
          </channel>
        </rss>
        """

        let metadata = try UpdateMetadataParser().parse(data: Data(xml.utf8))

        XCTAssertEqual(metadata.shortVersion, "1.2.0")
        XCTAssertEqual(metadata.buildVersion, "42")
        XCTAssertEqual(metadata.releaseNotesHTML, "<p>Improved launcher refresh.</p>")
    }

    func testWindowHelperIdentifierUsesMainAppBundlePrefix() {
        XCTAssertEqual(WindowHelperConfiguration.loginItemIdentifier, "com.minepacu.GatherApps.WindowHelper")
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

    func testDeletingGroupRemovesPersistedGroupAndGeneratedLauncher() throws {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsDeleteGroupTests-\(UUID().uuidString)", isDirectory: true)
        let groupsFileURL = testDirectory.appendingPathComponent("groups.json")
        let launchersDirectory = testDirectory.appendingPathComponent("Launchers", isDirectory: true)
        let runtimeExecutableURL = testDirectory
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        defer {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        try FileManager.default.createDirectory(
            at: runtimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeExecutableURL.path)

        let launcherGenerator = LauncherAppGeneratorService(
            launcherRuntimeExecutableURL: runtimeExecutableURL,
            defaultDestinationDirectory: launchersDirectory
        )
        let store = AppGroupStore(
            groupsFileURL: groupsFileURL,
            launcherGeneratorService: launcherGenerator
        )
        store.createGroup(named: "Dev/Test")
        let group = try XCTUnwrap(store.groups.first)
        store.generateLauncher(for: group.id)
        let launcherURL = try launcherGenerator.launcherURL(for: group)

        XCTAssertTrue(FileManager.default.fileExists(atPath: launcherURL.path))

        store.deleteGroup(id: group.id)

        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: launcherURL.path))

        let savedData = try Data(contentsOf: groupsFileURL)
        let savedGroups = try JSONDecoder().decode([AppGroup].self, from: savedData)
        XCTAssertTrue(savedGroups.isEmpty)
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
            .appendingPathComponent("GatherAppsLauncherTests-\(UUID().uuidString)", isDirectory: true)
        let runtimeExecutableURL = destination
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: runtimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeExecutableURL.path)

        let result = try LauncherAppGeneratorService(launcherRuntimeExecutableURL: runtimeExecutableURL)
            .generateLauncher(for: group, destinationDirectory: destination)

        let infoPlistURL = result.appURL.appendingPathComponent("Contents/Info.plist")
        let executableURL = result.appURL.appendingPathComponent("Contents/MacOS/GatherAppsLauncher")
        let iconURL = result.appURL.appendingPathComponent("Contents/Resources/GroupIcon.icns")

        XCTAssertTrue(FileManager.default.fileExists(atPath: infoPlistURL.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executableURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path))

        let infoData = try Data(contentsOf: infoPlistURL)
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(info["CFBundleName"] as? String, "GatherApps - Dev-Test")
        XCTAssertEqual(info["GatherAppsGroupID"] as? String, group.id.uuidString)
        XCTAssertEqual(info["GatherAppsShowsGatherAppsWindow"] as? Bool, false)
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, result.bundleIdentifier)
        XCTAssertNil(info["LSUIElement"])
        XCTAssertNil(info["LSBackgroundOnly"])
    }

    func testLauncherGeneratorCanCreateLauncherThatShowsGatherAppsWindow() throws {
        let group = AppGroup(name: "Visible Window")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsLauncherWindowPolicyTests-\(UUID().uuidString)", isDirectory: true)
        let runtimeExecutableURL = destination
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: runtimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeExecutableURL.path)

        let result = try LauncherAppGeneratorService(launcherRuntimeExecutableURL: runtimeExecutableURL)
            .generateLauncher(for: group, showsGatherAppsWindow: true, destinationDirectory: destination)

        let infoPlistURL = result.appURL.appendingPathComponent("Contents/Info.plist")
        let infoData = try Data(contentsOf: infoPlistURL)
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(info["GatherAppsShowsGatherAppsWindow"] as? Bool, true)
    }

    func testLauncherGeneratorDefaultsToUserApplicationsLaunchersDirectory() throws {
        let runtimeExecutableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsLauncherDefaultDestinationRuntime-\(UUID().uuidString)")
        try Self.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
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
            .appendingPathComponent("GatherAppsLauncherRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        let runtimeExecutableURL = destination
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: runtimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let runtimeContents = try Self.writeRuntimeExecutable(
            named: "compiled foreground runtime",
            to: runtimeExecutableURL
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeExecutableURL.path)

        let result = try LauncherAppGeneratorService(launcherRuntimeExecutableURL: runtimeExecutableURL)
            .generateLauncher(for: group, destinationDirectory: destination)

        let executableURL = result.appURL.appendingPathComponent("Contents/MacOS/GatherAppsLauncher")
        let generatedContents = try String(contentsOf: executableURL, encoding: .utf8)

        XCTAssertEqual(generatedContents, runtimeContents)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executableURL.path))
    }

    func testLauncherGeneratorRegeneratesExistingLauncherWhenRuntimeIsStale() throws {
        let group = AppGroup(name: "Refreshable", launcherShowsGatherAppsWindow: true)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsLauncherRefreshTests-\(UUID().uuidString)", isDirectory: true)
        let oldRuntimeExecutableURL = destination
            .appendingPathComponent("OldRuntime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        let currentRuntimeExecutableURL = destination
            .appendingPathComponent("CurrentRuntime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: oldRuntimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: currentRuntimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeRuntimeExecutable(named: "old runtime", to: oldRuntimeExecutableURL)
        let currentRuntimeContents = try Self.writeRuntimeExecutable(
            named: "current runtime",
            to: currentRuntimeExecutableURL
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldRuntimeExecutableURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: currentRuntimeExecutableURL.path)

        let oldGenerator = LauncherAppGeneratorService(launcherRuntimeExecutableURL: oldRuntimeExecutableURL)
        let result = try oldGenerator.generateLauncher(
            for: group,
            showsGatherAppsWindow: false,
            destinationDirectory: destination
        )
        let currentGenerator = LauncherAppGeneratorService(launcherRuntimeExecutableURL: currentRuntimeExecutableURL)

        let regenerated = try currentGenerator.regenerateLauncherIfStale(
            for: group,
            destinationDirectory: destination
        )

        let executableURL = result.appURL.appendingPathComponent("Contents/MacOS/GatherAppsLauncher")
        let infoPlistURL = result.appURL.appendingPathComponent("Contents/Info.plist")
        let infoData = try Data(contentsOf: infoPlistURL)
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        )

        XCTAssertTrue(regenerated)
        XCTAssertEqual(try String(contentsOf: executableURL, encoding: .utf8), currentRuntimeContents)
        XCTAssertEqual(info["GatherAppsShowsGatherAppsWindow"] as? Bool, true)
    }

    func testLauncherGeneratorTerminatesRegeneratesAndRelaunchesRunningStaleLauncher() throws {
        let group = AppGroup(name: "Running Stale")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsRunningStaleLauncherTests-\(UUID().uuidString)", isDirectory: true)
        let oldRuntimeExecutableURL = destination
            .appendingPathComponent("OldRuntime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        let currentRuntimeExecutableURL = destination
            .appendingPathComponent("CurrentRuntime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: oldRuntimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: currentRuntimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeRuntimeExecutable(named: "old runtime", to: oldRuntimeExecutableURL)
        try Self.writeRuntimeExecutable(named: "current runtime", to: currentRuntimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldRuntimeExecutableURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: currentRuntimeExecutableURL.path)

        _ = try LauncherAppGeneratorService(launcherRuntimeExecutableURL: oldRuntimeExecutableURL)
            .generateLauncher(for: group, destinationDirectory: destination)
        let lifecycleManager = StubLauncherAppLifecycleManager(runningBundleIdentifiers: [
            Self.launcherBundleIdentifier(for: group)
        ])
        let currentGenerator = LauncherAppGeneratorService(
            launcherRuntimeExecutableURL: currentRuntimeExecutableURL,
            launcherAppLifecycleManager: lifecycleManager
        )

        let regenerated = try currentGenerator.regenerateLauncherIfStale(
            for: group,
            destinationDirectory: destination
        )

        let launcherURL = try currentGenerator.launcherURL(for: group, destinationDirectory: destination)
        XCTAssertTrue(regenerated)
        XCTAssertEqual(lifecycleManager.events, [
            .checkedRunning(Self.launcherBundleIdentifier(for: group)),
            .terminated(Self.launcherBundleIdentifier(for: group)),
            .launched(launcherURL)
        ])
    }

    func testLauncherGeneratorDoesNotRelaunchNonRunningStaleLauncher() throws {
        let group = AppGroup(name: "Non Running Stale")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsNonRunningStaleLauncherTests-\(UUID().uuidString)", isDirectory: true)
        let oldRuntimeExecutableURL = destination
            .appendingPathComponent("OldRuntime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        let currentRuntimeExecutableURL = destination
            .appendingPathComponent("CurrentRuntime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: oldRuntimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: currentRuntimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeRuntimeExecutable(named: "old runtime", to: oldRuntimeExecutableURL)
        try Self.writeRuntimeExecutable(named: "current runtime", to: currentRuntimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldRuntimeExecutableURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: currentRuntimeExecutableURL.path)

        _ = try LauncherAppGeneratorService(launcherRuntimeExecutableURL: oldRuntimeExecutableURL)
            .generateLauncher(for: group, destinationDirectory: destination)
        let lifecycleManager = StubLauncherAppLifecycleManager()
        let currentGenerator = LauncherAppGeneratorService(
            launcherRuntimeExecutableURL: currentRuntimeExecutableURL,
            launcherAppLifecycleManager: lifecycleManager
        )

        let regenerated = try currentGenerator.regenerateLauncherIfStale(
            for: group,
            destinationDirectory: destination
        )

        XCTAssertTrue(regenerated)
        XCTAssertEqual(lifecycleManager.events, [
            .checkedRunning(Self.launcherBundleIdentifier(for: group))
        ])
    }

    func testLauncherGeneratorDoesNotTerminateCurrentRunningLauncher() throws {
        let group = AppGroup(name: "Current Running")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsCurrentRunningLauncherTests-\(UUID().uuidString)", isDirectory: true)
        let runtimeExecutableURL = destination
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: runtimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeExecutableURL.path)

        let lifecycleManager = StubLauncherAppLifecycleManager(runningBundleIdentifiers: [
            Self.launcherBundleIdentifier(for: group)
        ])
        let generator = LauncherAppGeneratorService(
            launcherRuntimeExecutableURL: runtimeExecutableURL,
            launcherAppLifecycleManager: lifecycleManager
        )
        _ = try generator.generateLauncher(for: group, destinationDirectory: destination)

        let regenerated = try generator.regenerateLauncherIfStale(
            for: group,
            destinationDirectory: destination
        )

        XCTAssertFalse(regenerated)
        XCTAssertEqual(lifecycleManager.events, [])
    }

    func testLauncherGeneratorForceTerminatesBeforeRegeneratingWhenGracefulTerminationFails() throws {
        let group = AppGroup(name: "Force Terminate")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsForceTerminateLauncherTests-\(UUID().uuidString)", isDirectory: true)
        let oldRuntimeExecutableURL = destination
            .appendingPathComponent("OldRuntime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        let currentRuntimeExecutableURL = destination
            .appendingPathComponent("CurrentRuntime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: oldRuntimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: currentRuntimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeRuntimeExecutable(named: "old runtime", to: oldRuntimeExecutableURL)
        try Self.writeRuntimeExecutable(named: "current runtime", to: currentRuntimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldRuntimeExecutableURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: currentRuntimeExecutableURL.path)

        _ = try LauncherAppGeneratorService(launcherRuntimeExecutableURL: oldRuntimeExecutableURL)
            .generateLauncher(for: group, destinationDirectory: destination)
        let lifecycleManager = StubLauncherAppLifecycleManager(
            runningBundleIdentifiers: [Self.launcherBundleIdentifier(for: group)],
            gracefulTerminationSucceeds: false
        )
        let currentGenerator = LauncherAppGeneratorService(
            launcherRuntimeExecutableURL: currentRuntimeExecutableURL,
            launcherAppLifecycleManager: lifecycleManager
        )

        let regenerated = try currentGenerator.regenerateLauncherIfStale(
            for: group,
            destinationDirectory: destination
        )

        let launcherURL = try currentGenerator.launcherURL(for: group, destinationDirectory: destination)
        XCTAssertTrue(regenerated)
        XCTAssertEqual(lifecycleManager.events, [
            .checkedRunning(Self.launcherBundleIdentifier(for: group)),
            .terminated(Self.launcherBundleIdentifier(for: group)),
            .forceTerminated(Self.launcherBundleIdentifier(for: group)),
            .launched(launcherURL)
        ])
    }

    func testLauncherGeneratorIgnoresMissingLauncherDuringStaleCheck() throws {
        let group = AppGroup(name: "Missing Launcher")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsMissingLauncherRefreshTests-\(UUID().uuidString)", isDirectory: true)
        let runtimeExecutableURL = destination
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: runtimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeExecutableURL.path)

        let regenerated = try LauncherAppGeneratorService(launcherRuntimeExecutableURL: runtimeExecutableURL)
            .regenerateLauncherIfStale(for: group, destinationDirectory: destination)

        XCTAssertFalse(regenerated)
    }

    func testLauncherGeneratorDoesNotRegenerateCurrentLauncher() throws {
        let group = AppGroup(name: "Current Launcher")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsCurrentLauncherTests-\(UUID().uuidString)", isDirectory: true)
        let runtimeExecutableURL = destination
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        let appBundleURL = destination.appendingPathComponent("GatherApps.app", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: runtimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: appBundleURL, withIntermediateDirectories: true)
        try Self.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeExecutableURL.path)

        let generator = LauncherAppGeneratorService(
            launcherRuntimeExecutableURL: runtimeExecutableURL,
            appBundleURL: appBundleURL
        )
        _ = try generator.generateLauncher(for: group, destinationDirectory: destination)

        let regenerated = try generator.regenerateLauncherIfStale(
            for: group,
            destinationDirectory: destination
        )

        XCTAssertFalse(regenerated)
    }

    func testLauncherGeneratorRegeneratesLauncherWhenAppBundlePathIsStale() throws {
        let group = AppGroup(name: "App Path")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsLauncherAppPathTests-\(UUID().uuidString)", isDirectory: true)
        let runtimeExecutableURL = destination
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        let oldAppBundleURL = destination.appendingPathComponent("OldGatherApps.app", isDirectory: true)
        let currentAppBundleURL = destination.appendingPathComponent("GatherApps.app", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: runtimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: oldAppBundleURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: currentAppBundleURL, withIntermediateDirectories: true)
        try Self.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeExecutableURL.path)

        _ = try LauncherAppGeneratorService(
            launcherRuntimeExecutableURL: runtimeExecutableURL,
            appBundleURL: oldAppBundleURL
        ).generateLauncher(for: group, destinationDirectory: destination)
        let currentGenerator = LauncherAppGeneratorService(
            launcherRuntimeExecutableURL: runtimeExecutableURL,
            appBundleURL: currentAppBundleURL
        )

        let regenerated = try currentGenerator.regenerateLauncherIfStale(
            for: group,
            destinationDirectory: destination
        )

        let launcherURL = try currentGenerator.launcherURL(for: group, destinationDirectory: destination)
        let info = try Self.infoPlist(at: launcherURL)

        XCTAssertTrue(regenerated)
        XCTAssertEqual(info["GatherAppsApplicationPath"] as? String, currentAppBundleURL.path)
    }

    func testLauncherGeneratorRegeneratesLauncherWhenSchemaMetadataIsMissing() throws {
        let group = AppGroup(name: "Schema")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsLauncherSchemaTests-\(UUID().uuidString)", isDirectory: true)
        let runtimeExecutableURL = destination
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: runtimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeExecutableURL.path)

        let generator = LauncherAppGeneratorService(launcherRuntimeExecutableURL: runtimeExecutableURL)
        let result = try generator.generateLauncher(for: group, destinationDirectory: destination)
        let infoPlistURL = result.appURL.appendingPathComponent("Contents/Info.plist")
        var info = try Self.infoPlist(at: result.appURL)
        info.removeValue(forKey: "GatherAppsLauncherSchemaVersion")
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: infoPlistURL, options: .atomic)

        let regenerated = try generator.regenerateLauncherIfStale(
            for: group,
            destinationDirectory: destination
        )

        XCTAssertTrue(regenerated)
        XCTAssertNotNil(try Self.infoPlist(at: result.appURL)["GatherAppsLauncherSchemaVersion"])
    }

    func testAppGroupStorePersistsLauncherWindowPolicyAndRegeneratesStaleLaunchersOnLoad() throws {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsStoreLauncherRefreshTests-\(UUID().uuidString)", isDirectory: true)
        let groupsFileURL = testDirectory.appendingPathComponent("groups.json")
        let launchersDirectory = testDirectory.appendingPathComponent("Launchers", isDirectory: true)
        let oldRuntimeExecutableURL = testDirectory
            .appendingPathComponent("OldRuntime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        let currentRuntimeExecutableURL = testDirectory
            .appendingPathComponent("CurrentRuntime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        defer {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        try FileManager.default.createDirectory(
            at: groupsFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: oldRuntimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: currentRuntimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeRuntimeExecutable(named: "old runtime", to: oldRuntimeExecutableURL)
        let currentRuntimeContents = try Self.writeRuntimeExecutable(
            named: "current runtime",
            to: currentRuntimeExecutableURL
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldRuntimeExecutableURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: currentRuntimeExecutableURL.path)

        let group = AppGroup(name: "Persisted", launcherShowsGatherAppsWindow: true)
        let oldGenerator = LauncherAppGeneratorService(
            launcherRuntimeExecutableURL: oldRuntimeExecutableURL,
            defaultDestinationDirectory: launchersDirectory
        )
        let oldResult = try oldGenerator.generateLauncher(for: group, showsGatherAppsWindow: false)
        let groupsData = try JSONEncoder().encode([group])
        try groupsData.write(to: groupsFileURL, options: .atomic)

        _ = AppGroupStore(
            groupsFileURL: groupsFileURL,
            launcherGeneratorService: LauncherAppGeneratorService(
                launcherRuntimeExecutableURL: currentRuntimeExecutableURL,
                defaultDestinationDirectory: launchersDirectory
            )
        )

        let executableURL = oldResult.appURL.appendingPathComponent("Contents/MacOS/GatherAppsLauncher")
        let infoPlistURL = oldResult.appURL.appendingPathComponent("Contents/Info.plist")
        let infoData = try Data(contentsOf: infoPlistURL)
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(try String(contentsOf: executableURL, encoding: .utf8), currentRuntimeContents)
        XCTAssertEqual(info["GatherAppsShowsGatherAppsWindow"] as? Bool, true)
    }

    func testGeneratingLauncherPersistsLauncherWindowPolicy() throws {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsLauncherPolicyPersistTests-\(UUID().uuidString)", isDirectory: true)
        let groupsFileURL = testDirectory.appendingPathComponent("groups.json")
        let launchersDirectory = testDirectory.appendingPathComponent("Launchers", isDirectory: true)
        let runtimeExecutableURL = testDirectory
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        defer {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        try FileManager.default.createDirectory(
            at: runtimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeExecutableURL.path)

        let store = AppGroupStore(
            groupsFileURL: groupsFileURL,
            launcherGeneratorService: LauncherAppGeneratorService(
                launcherRuntimeExecutableURL: runtimeExecutableURL,
                defaultDestinationDirectory: launchersDirectory
            )
        )
        store.createGroup(named: "Persist Policy")
        let group = try XCTUnwrap(store.groups.first)

        store.generateLauncher(for: group.id, showsGatherAppsWindow: true)

        let savedData = try Data(contentsOf: groupsFileURL)
        let savedGroups = try JSONDecoder().decode([AppGroup].self, from: savedData)

        XCTAssertEqual(store.groups.first?.launcherShowsGatherAppsWindow, true)
        XCTAssertEqual(savedGroups.first?.launcherShowsGatherAppsWindow, true)
    }

    private static func localizationKeys(at url: URL) throws -> Set<String> {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let strings = try XCTUnwrap(plist as? [String: String])
        return Set(strings.keys)
    }

    private static func infoPlist(at appURL: URL) throws -> [String: Any] {
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let infoData = try Data(contentsOf: infoPlistURL)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        )
    }

    @discardableResult
    private static func writeRuntimeExecutable(named name: String, to url: URL) throws -> String {
        let contents = """
        #!/bin/sh
        # \(name)
        exit 0

        """
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return contents
    }

    private static func launcherBundleIdentifier(for group: AppGroup) -> String {
        "com.minepacu.GatherApps.launcher.\(group.id.uuidString.lowercased())"
    }
}

private final class StubLauncherAppLifecycleManager: LauncherAppLifecycleManaging {
    enum Event: Equatable {
        case checkedRunning(String)
        case terminated(String)
        case forceTerminated(String)
        case launched(URL)
    }

    private let runningBundleIdentifiers: Set<String>
    private let gracefulTerminationSucceeds: Bool
    private(set) var events: [Event] = []

    init(
        runningBundleIdentifiers: Set<String> = [],
        gracefulTerminationSucceeds: Bool = true
    ) {
        self.runningBundleIdentifiers = runningBundleIdentifiers
        self.gracefulTerminationSucceeds = gracefulTerminationSucceeds
    }

    func isLauncherRunning(bundleIdentifier: String) -> Bool {
        events.append(.checkedRunning(bundleIdentifier))
        return runningBundleIdentifiers.contains(bundleIdentifier)
    }

    func terminateLauncher(bundleIdentifier: String) -> Bool {
        events.append(.terminated(bundleIdentifier))
        return gracefulTerminationSucceeds
    }

    func forceTerminateLauncher(bundleIdentifier: String) {
        events.append(.forceTerminated(bundleIdentifier))
    }

    func launchLauncher(at appURL: URL) {
        events.append(.launched(appURL))
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
