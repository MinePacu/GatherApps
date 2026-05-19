import AppKit
import XCTest
@testable import GatherApps

@MainActor
final class AppGroupStoreTests: XCTestCase {
    func testCoordinatorRoutesSharedActionsThroughStoreAndSwitcher() throws {
        let groupID = UUID()
        let group = AppGroup(
            id: groupID,
            name: "Design",
            apps: [
                GroupedApp(bundleIdentifier: "com.example.Design", name: "Design", appPath: nil)
            ],
            iconFileName: "existing-icon.icns"
        )
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
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
        var didShowSwitcher = false
        var didShowMainWindow = false
        let coordinator = GatherAppsAppCoordinator(
            store: store,
            showSwitcherAction: { _ in didShowSwitcher = true },
            activateAppAction: {}
        )
        coordinator.showMainWindowAction = {
            didShowMainWindow = true
        }

        coordinator.activateGroup(id: groupID)
        coordinator.showSwitcher()
        coordinator.showMainWindow()

        XCTAssertEqual(activationService.requestedBundleIdentifiers, ["com.example.Design"])
        XCTAssertTrue(didShowSwitcher)
        XCTAssertTrue(didShowMainWindow)
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

    @discardableResult
    private static func writeRuntimeExecutable(named name: String, to url: URL) throws -> Data {
        let fixtureURL = runtimeFixtureURL(named: name)
        let contents = try Data(contentsOf: fixtureURL)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.copyItem(at: fixtureURL, to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return contents
    }

    private static func runtimeFixtureURL(named name: String) -> URL {
        let path: String
        switch name {
        case "old runtime":
            path = "/usr/bin/false"
        case "current runtime":
            path = "/bin/echo"
        default:
            path = "/usr/bin/true"
        }
        return URL(fileURLWithPath: path)
    }

}
