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

    func testGroupedAppDecodesLegacyBundleAppAsBundleTarget() throws {
        let json = """
        {
          "bundleIdentifier": "com.example.Legacy",
          "name": "Legacy",
          "appPath": "/Applications/Legacy.app"
        }
        """

        let app = try JSONDecoder().decode(GroupedApp.self, from: Data(json.utf8))

        XCTAssertEqual(app.kind, .bundle)
        XCTAssertEqual(app.id, "com.example.Legacy")
        XCTAssertEqual(app.bundleIdentifier, "com.example.Legacy")
        XCTAssertEqual(app.appPath, "/Applications/Legacy.app")
        XCTAssertNil(app.executablePath)
    }

    func testExecutableGroupedAppUsesExecutablePathAsStableID() {
        let app = GroupedApp(
            executablePath: "/opt/homebrew/bin/scrcpy",
            name: "scrcpy",
            appPath: nil
        )

        XCTAssertEqual(app.kind, .executable)
        XCTAssertEqual(app.id, "executable:/opt/homebrew/bin/scrcpy")
        XCTAssertEqual(app.bundleIdentifier, "executable:/opt/homebrew/bin/scrcpy")
        XCTAssertEqual(app.executablePath, "/opt/homebrew/bin/scrcpy")
    }

    func testGroupActivationRaisesAppsSoGroupOrderDeterminesFrontmostApp() throws {
        let groupID = UUID()
        let group = AppGroup(
            id: groupID,
            name: "Ordered",
            apps: [
                GroupedApp(bundleIdentifier: "com.example.First", name: "First", appPath: nil),
                GroupedApp(bundleIdentifier: "com.example.Second", name: "Second", appPath: nil),
                GroupedApp(bundleIdentifier: "com.example.Third", name: "Third", appPath: nil)
            ],
            iconFileName: "existing-icon.icns"
        )
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsActivationOrderTests-\(UUID().uuidString)", isDirectory: true)
        let groupsFileURL = testDirectory.appendingPathComponent("groups.json")
        defer {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode([group]).write(to: groupsFileURL, options: .atomic)
        let activationService = StubAppActivationService()
        let store = AppGroupStore(
            groupsFileURL: groupsFileURL,
            activationService: activationService
        )

        store.activate(groupID: groupID)

        XCTAssertEqual(activationService.requestedApps.map(\.id), [
            "com.example.Third",
            "com.example.Second",
            "com.example.First"
        ])
        XCTAssertEqual(store.lastActivationResults, [
            .success(appName: "First"),
            .success(appName: "Second"),
            .success(appName: "Third")
        ])
    }

    func testGroupActivationActivatesExecutableTargets() throws {
        let groupID = UUID()
        let executable = GroupedApp(
            executablePath: "/opt/homebrew/bin/scrcpy",
            name: "scrcpy",
            appPath: nil
        )
        let group = AppGroup(
            id: groupID,
            name: "Device",
            apps: [executable],
            iconFileName: "existing-icon.icns"
        )
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsExecutableActivationTests-\(UUID().uuidString)", isDirectory: true)
        let groupsFileURL = testDirectory.appendingPathComponent("groups.json")
        defer {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode([group]).write(to: groupsFileURL, options: .atomic)
        let activationService = StubAppActivationService()
        let store = AppGroupStore(
            groupsFileURL: groupsFileURL,
            activationService: activationService
        )

        store.activate(groupID: groupID)

        XCTAssertEqual(activationService.requestedApps, [executable])
        XCTAssertEqual(store.lastActivationResults, [
            .success(appName: "scrcpy")
        ])
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

    func testAppcastFeedProviderUsesGitLabBeforeGitHubFallback() {
        var provider = AppcastFeedProvider()

        XCTAssertEqual(
            provider.currentFeedURL?.absoluteString,
            "https://gitlab.com/MinePacu/GatherApps/-/releases/permalink/latest/downloads/appcast.xml"
        )

        XCTAssertTrue(provider.advanceToFallbackFeed())
        XCTAssertEqual(
            provider.currentFeedURL?.absoluteString,
            "https://github.com/MinePacu/GatherApps/releases/latest/download/appcast.xml"
        )
        XCTAssertFalse(provider.advanceToFallbackFeed())
    }

    func testGitLabCIAddsMacOSBuildAndTestPipeline() throws {
        let projectRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let gitLabCIURL = projectRootURL.appendingPathComponent(".gitlab-ci.yml")
        let gitLabCI = try String(contentsOf: gitLabCIURL, encoding: .utf8)

        XCTAssertTrue(gitLabCI.contains("workflow:"))
        XCTAssertTrue(gitLabCI.contains("$CI_PIPELINE_SOURCE == \"merge_request_event\""))
        XCTAssertTrue(gitLabCI.contains("- macos"))
        XCTAssertFalse(gitLabCI.contains("- mac\n"))
        XCTAssertTrue(gitLabCI.contains("self-hosted macOS runner"))
        XCTAssertFalse(gitLabCI.contains("saas-macos-medium-m1"))
        XCTAssertFalse(gitLabCI.contains("image: macos-26-xcode-26"))
        XCTAssertTrue(gitLabCI.contains("xcodebuild build"))
        XCTAssertTrue(gitLabCI.contains("xcodebuild test"))
        XCTAssertTrue(gitLabCI.contains("CODE_SIGNING_ALLOWED=NO"))
        XCTAssertTrue(gitLabCI.contains("reports:"))
        XCTAssertTrue(gitLabCI.contains("junit: TestReports/junit.xml"))
        XCTAssertTrue(gitLabCI.contains("launcher-integration-test:"))
        XCTAssertTrue(gitLabCI.contains("allow_failure: false"))
        XCTAssertTrue(gitLabCI.contains("codequality: CodeQuality/gl-code-quality-report.json"))
        XCTAssertTrue(gitLabCI.contains("template: Jobs/SAST.gitlab-ci.yml"))
        XCTAssertTrue(gitLabCI.contains("template: Jobs/Secret-Detection.gitlab-ci.yml"))
        XCTAssertTrue(gitLabCI.contains("sast:\n  stage: security"))
        XCTAssertTrue(gitLabCI.contains("secret_detection:\n  stage: security"))
        XCTAssertTrue(gitLabCI.contains("AST_ENABLE_MR_PIPELINES: \"true\""))
    }

    func testWindowHelperIdentifierUsesMainAppBundlePrefix() {
        XCTAssertEqual(WindowHelperConfiguration.loginItemIdentifier, "com.minepacu.GatherApps.WindowHelper")
    }

    func testRunningAppServiceReturnsOneAppPerTargetIdentifier() {
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
            ),
            RunningAppInfo(
                executablePath: "/opt/homebrew/bin/scrcpy",
                name: "scrcpy"
            ),
            RunningAppInfo(
                executablePath: "/opt/homebrew/bin/scrcpy",
                name: "scrcpy"
            )
        ]

        let uniqueApps = RunningAppService.uniqueApps(apps)

        XCTAssertEqual(uniqueApps.map(\.id), [
            duplicateBundleID,
            "executable:/opt/homebrew/bin/scrcpy",
            "com.apple.TextEdit"
        ])
    }

    func testRunningAppServiceBuildsExecutableAppsFromVisibleNonBundleWindows() {
        let windows: [[String: Any]] = [
            [
                kCGWindowOwnerName as String: "scrcpy",
                kCGWindowOwnerPID as String: NSNumber(value: 1234),
                kCGWindowLayer as String: NSNumber(value: 0)
            ],
            [
                kCGWindowOwnerName as String: "Menu Extra",
                kCGWindowOwnerPID as String: NSNumber(value: 5678),
                kCGWindowLayer as String: NSNumber(value: 25)
            ],
            [
                kCGWindowOwnerName as String: "TextEdit",
                kCGWindowOwnerPID as String: NSNumber(value: 9999),
                kCGWindowLayer as String: NSNumber(value: 0)
            ]
        ]

        let apps = RunningAppService.executableApps(
            from: windows,
            excludingProcessIDs: [9999],
            executablePathForProcessID: { processID in
                processID == 1234 ? "/opt/homebrew/bin/scrcpy" : nil
            }
        )

        XCTAssertEqual(apps, [
            RunningAppInfo(
                executablePath: "/opt/homebrew/bin/scrcpy",
                name: "scrcpy",
                processIdentifier: 1234
            )
        ])
    }

    func testRunningAppServiceOnlyExcludesBundleBackedWorkspaceAppsFromExecutableDiscovery() {
        let bundledApp = StubWorkspaceRunningApp(
            processIdentifier: 1111,
            bundleIdentifier: "com.apple.TextEdit",
            localizedName: "TextEdit",
            bundleURL: URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        )
        let nonBundleApp = StubWorkspaceRunningApp(
            processIdentifier: 2222,
            bundleIdentifier: nil,
            localizedName: "scrcpy",
            bundleURL: URL(fileURLWithPath: "/opt/homebrew/Cellar/scrcpy/4.0/bin/scrcpy")
        )

        let excludedProcessIDs = RunningAppService.bundleBackedProcessIDs(from: [
            bundledApp,
            nonBundleApp
        ])

        XCTAssertEqual(excludedProcessIDs, [1111])
    }

    func testStatusBarMenuModelDisablesEmptyGroupsAndShowsRunningCounts() {
        let groups = [
            AppGroup(
                name: "Writing",
                apps: [
                    GroupedApp(bundleIdentifier: "com.apple.TextEdit", name: "TextEdit", appPath: nil),
                    GroupedApp(bundleIdentifier: "com.apple.Notes", name: "Notes", appPath: nil)
                ]
            ),
            AppGroup(
                name: "Device",
                apps: [
                    GroupedApp(executablePath: "/opt/homebrew/bin/scrcpy", name: "scrcpy", appPath: nil)
                ]
            ),
            AppGroup(name: "Empty")
        ]

        let items = StatusBarMenuModel.groupItems(
            for: groups,
            runningAppIdentifiers: [
                "com.apple.TextEdit",
                "executable:/opt/homebrew/bin/scrcpy"
            ]
        )

        XCTAssertEqual(items.map(\.title), ["Activate Writing", "Activate Device", "Activate Empty"])
        XCTAssertEqual(items.map(\.runningCountTitle), ["1/2 running", "1/1 running", "0/0 running"])
        XCTAssertEqual(items.map(\.isEnabled), [true, true, false])
    }

    private static func localizationKeys(at url: URL) throws -> Set<String> {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let strings = try XCTUnwrap(plist as? [String: String])
        return Set(strings.keys)
    }

}

private struct StubWorkspaceRunningApp: WorkspaceRunningApplication {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String?
    let bundleURL: URL?
}
