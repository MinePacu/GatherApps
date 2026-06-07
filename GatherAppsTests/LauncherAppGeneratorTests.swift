import XCTest
@testable import GatherApps

@MainActor
final class LauncherAppGeneratorTests: XCTestCase {
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
        try LauncherTestSupport.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
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
        try LauncherTestSupport.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
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
        try LauncherTestSupport.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
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
        let runtimeContents = try LauncherTestSupport.writeRuntimeExecutable(
            named: "compiled foreground runtime",
            to: runtimeExecutableURL
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeExecutableURL.path)

        let result = try LauncherAppGeneratorService(launcherRuntimeExecutableURL: runtimeExecutableURL)
            .generateLauncher(for: group, destinationDirectory: destination)

        let executableURL = result.appURL.appendingPathComponent("Contents/MacOS/GatherAppsLauncher")
        let generatedContents = try Data(contentsOf: executableURL)

        XCTAssertEqual(generatedContents, runtimeContents)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executableURL.path))
    }

    func testLauncherGeneratorDoesNotPersistReplacementPNGWhenReferencedIconIsMissing() throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsLauncherMissingPNGTests-\(UUID().uuidString)", isDirectory: true)
        let runtimeExecutableURL = destination
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        let iconsDirectory = destination.appendingPathComponent("Icons", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: runtimeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try LauncherTestSupport.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeExecutableURL.path)

        let group = AppGroup(name: "Dev/Test", iconFileName: "missing.png")
        let generator = LauncherAppGeneratorService(
            iconService: GroupIconService(iconsDirectoryURL: iconsDirectory),
            launcherRuntimeExecutableURL: runtimeExecutableURL
        )
        let result = try generator.generateLauncher(for: group, destinationDirectory: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.appURL.appendingPathComponent("Contents/Resources/GroupIcon.icns").path))
        let iconFiles = try FileManager.default.contentsOfDirectory(
            at: iconsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        XCTAssertTrue(iconFiles.isEmpty)
    }

}
