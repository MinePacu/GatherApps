import XCTest
@testable import GatherApps

@MainActor
final class LauncherAppMetadataTests: XCTestCase {
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
        try LauncherTestSupport.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
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
        let info = try LauncherTestSupport.infoPlist(at: launcherURL)

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
        try LauncherTestSupport.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeExecutableURL.path)

        let generator = LauncherAppGeneratorService(launcherRuntimeExecutableURL: runtimeExecutableURL)
        let result = try generator.generateLauncher(for: group, destinationDirectory: destination)
        let infoPlistURL = result.appURL.appendingPathComponent("Contents/Info.plist")
        var info = try LauncherTestSupport.infoPlist(at: result.appURL)
        info.removeValue(forKey: "GatherAppsLauncherSchemaVersion")
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: infoPlistURL, options: .atomic)

        let regenerated = try generator.regenerateLauncherIfStale(
            for: group,
            destinationDirectory: destination
        )

        XCTAssertTrue(regenerated)
        XCTAssertNotNil(try LauncherTestSupport.infoPlist(at: result.appURL)["GatherAppsLauncherSchemaVersion"])
    }

    func testAppGroupStorePersistsLauncherWindowPolicyAndRegeneratesStaleLaunchersOnLoad() throws {
        let fixture = try LauncherTestSupport.makeStoreRefreshFixture()
        defer {
            try? FileManager.default.removeItem(at: fixture.testDirectory)
        }

        let group = AppGroup(name: "Persisted", launcherShowsGatherAppsWindow: true)
        let oldGenerator = LauncherAppGeneratorService(
            launcherRuntimeExecutableURL: fixture.oldRuntimeExecutableURL,
            defaultDestinationDirectory: fixture.launchersDirectory
        )
        let oldResult = try oldGenerator.generateLauncher(for: group, showsGatherAppsWindow: false)
        let groupsData = try JSONEncoder().encode([group])
        try groupsData.write(to: fixture.groupsFileURL, options: .atomic)

        _ = AppGroupStore(
            groupsFileURL: fixture.groupsFileURL,
            launcherGeneratorService: LauncherAppGeneratorService(
                launcherRuntimeExecutableURL: fixture.currentRuntimeExecutableURL,
                defaultDestinationDirectory: fixture.launchersDirectory
            )
        )

        let executableURL = oldResult.appURL.appendingPathComponent("Contents/MacOS/GatherAppsLauncher")
        let infoPlistURL = oldResult.appURL.appendingPathComponent("Contents/Info.plist")
        let infoData = try Data(contentsOf: infoPlistURL)
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(try Data(contentsOf: executableURL), fixture.currentRuntimeContents)
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
        try LauncherTestSupport.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
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

}
