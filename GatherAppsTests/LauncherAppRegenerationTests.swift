import XCTest
@testable import GatherApps

@MainActor
final class LauncherAppRegenerationTests: XCTestCase {
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
        try LauncherTestSupport.writeRuntimeExecutable(named: "old runtime", to: oldRuntimeExecutableURL)
        let currentRuntimeContents = try LauncherTestSupport.writeRuntimeExecutable(
            named: "current runtime",
            to: currentRuntimeExecutableURL
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldRuntimeExecutableURL.path)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: currentRuntimeExecutableURL.path
        )

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
        XCTAssertEqual(try Data(contentsOf: executableURL), currentRuntimeContents)
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
        try LauncherTestSupport.writeRuntimeExecutable(named: "old runtime", to: oldRuntimeExecutableURL)
        try LauncherTestSupport.writeRuntimeExecutable(named: "current runtime", to: currentRuntimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldRuntimeExecutableURL.path)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: currentRuntimeExecutableURL.path
        )

        _ = try LauncherAppGeneratorService(launcherRuntimeExecutableURL: oldRuntimeExecutableURL)
            .generateLauncher(for: group, destinationDirectory: destination)
        let lifecycleManager = StubLauncherAppLifecycleManager(runningBundleIdentifiers: [
            LauncherTestSupport.launcherBundleIdentifier(for: group)
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
            .checkedRunning(LauncherTestSupport.launcherBundleIdentifier(for: group)),
            .terminated(LauncherTestSupport.launcherBundleIdentifier(for: group)),
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
        try LauncherTestSupport.writeRuntimeExecutable(named: "old runtime", to: oldRuntimeExecutableURL)
        try LauncherTestSupport.writeRuntimeExecutable(named: "current runtime", to: currentRuntimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldRuntimeExecutableURL.path)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: currentRuntimeExecutableURL.path
        )

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
            .checkedRunning(LauncherTestSupport.launcherBundleIdentifier(for: group))
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
        try LauncherTestSupport.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeExecutableURL.path)

        let lifecycleManager = StubLauncherAppLifecycleManager(runningBundleIdentifiers: [
            LauncherTestSupport.launcherBundleIdentifier(for: group)
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

}
