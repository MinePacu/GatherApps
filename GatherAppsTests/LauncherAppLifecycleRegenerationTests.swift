import XCTest
@testable import GatherApps

@MainActor
final class LauncherAppLifecycleRegenerationTests: XCTestCase {
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
        try LauncherTestSupport.writeRuntimeExecutable(named: "old runtime", to: oldRuntimeExecutableURL)
        try LauncherTestSupport.writeRuntimeExecutable(named: "current runtime", to: currentRuntimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldRuntimeExecutableURL.path)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: currentRuntimeExecutableURL.path
        )

        _ = try LauncherAppGeneratorService(launcherRuntimeExecutableURL: oldRuntimeExecutableURL)
            .generateLauncher(for: group, destinationDirectory: destination)
        let lifecycleManager = StubLauncherAppLifecycleManager(
            runningBundleIdentifiers: [LauncherTestSupport.launcherBundleIdentifier(for: group)],
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
            .checkedRunning(LauncherTestSupport.launcherBundleIdentifier(for: group)),
            .terminated(LauncherTestSupport.launcherBundleIdentifier(for: group)),
            .forceTerminated(LauncherTestSupport.launcherBundleIdentifier(for: group)),
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
        try LauncherTestSupport.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
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
        try LauncherTestSupport.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
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

}
