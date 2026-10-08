import AppKit
import XCTest
@testable import GatherApps

@MainActor
final class AppGroupStorePersistenceTests: XCTestCase {
    func testCorruptGroupsFileIsBackedUpBeforeNextSave() throws {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsStoreCorruptBackupTests-\(UUID().uuidString)", isDirectory: true)
        let groupsFileURL = testDirectory.appendingPathComponent("groups.json")
        let iconsDirectory = testDirectory.appendingPathComponent("Icons", isDirectory: true)
        let corruptData = Data("not valid JSON".utf8)
        defer {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
        try corruptData.write(to: groupsFileURL)

        let store = AppGroupStore(
            groupsFileURL: groupsFileURL,
            iconService: GroupIconService(iconsDirectoryURL: iconsDirectory),
            iconCleanupService: GroupIconCleanupService(iconsDirectoryURL: iconsDirectory)
        )

        let backupFileNames = try FileManager.default.contentsOfDirectory(atPath: testDirectory.path)
            .filter { $0.hasPrefix("groups.json.corrupt-") }
        XCTAssertEqual(backupFileNames.count, 1)
        let backupFileName = try XCTUnwrap(backupFileNames.first)
        let backupURL = testDirectory.appendingPathComponent(backupFileName)
        XCTAssertEqual(try Data(contentsOf: backupURL), corruptData)

        store.createGroup(named: "New")

        XCTAssertEqual(try Data(contentsOf: backupURL), corruptData)
        let savedGroups = try JSONDecoder().decode([AppGroup].self, from: Data(contentsOf: groupsFileURL))
        XCTAssertEqual(savedGroups.map(\.name), ["New"])
    }

    func testSavingIsBlockedWhenCorruptGroupsFileCannotBeBackedUp() throws {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsStoreBlockedSaveTests-\(UUID().uuidString)", isDirectory: true)
        let groupsFileURL = testDirectory.appendingPathComponent("groups.json")
        let iconsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsStoreBlockedSaveIcons-\(UUID().uuidString)", isDirectory: true)
        let corruptData = Data("not valid JSON".utf8)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: testDirectory.path)
            try? FileManager.default.removeItem(at: testDirectory)
            try? FileManager.default.removeItem(at: iconsDirectory)
        }
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
        try corruptData.write(to: groupsFileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: testDirectory.path)

        let store = AppGroupStore(
            groupsFileURL: groupsFileURL,
            iconService: GroupIconService(iconsDirectoryURL: iconsDirectory),
            iconCleanupService: GroupIconCleanupService(iconsDirectoryURL: iconsDirectory)
        )

        store.createGroup(named: "New")

        XCTAssertEqual(try Data(contentsOf: groupsFileURL), corruptData)
        XCTAssertEqual(store.lastErrorMessage, L10n.string("errors.groupSaveBlockedByUnreadableFile"))
    }

    func testAddingAppIsPersistedWhenIconRegenerationFails() throws {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsStoreIconFailurePersistTests-\(UUID().uuidString)", isDirectory: true)
        let groupsFileURL = testDirectory.appendingPathComponent("groups.json")
        let iconsDirectory = testDirectory.appendingPathComponent("Icons", isDirectory: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: iconsDirectory.path)
            try? FileManager.default.removeItem(at: testDirectory)
        }
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)

        let store = AppGroupStore(
            groupsFileURL: groupsFileURL,
            iconService: GroupIconService(iconsDirectoryURL: iconsDirectory),
            iconCleanupService: GroupIconCleanupService(iconsDirectoryURL: iconsDirectory)
        )
        let groupID = try XCTUnwrap(store.createGroup(named: "Dev"))
        XCTAssertNil(store.lastErrorMessage)

        // Make the icons directory read-only so the next icon write fails.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: iconsDirectory.path)

        store.add(
            RunningAppInfo(
                bundleIdentifier: "com.apple.Safari",
                name: "Safari",
                appURL: URL(fileURLWithPath: "/Applications/Safari.app")
            ),
            to: groupID
        )

        XCTAssertNotNil(store.lastErrorMessage)
        XCTAssertEqual(store.groups.first?.apps.map(\.id), ["com.apple.Safari"])
        let savedGroups = try JSONDecoder().decode([AppGroup].self, from: Data(contentsOf: groupsFileURL))
        XCTAssertEqual(savedGroups.first?.apps.map(\.id), ["com.apple.Safari"])
    }

    func testCreateGroupReturnsNilForBlankName() throws {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsStoreBlankNameTests-\(UUID().uuidString)", isDirectory: true)
        let groupsFileURL = testDirectory.appendingPathComponent("groups.json")
        let iconsDirectory = testDirectory.appendingPathComponent("Icons", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)

        let store = AppGroupStore(
            groupsFileURL: groupsFileURL,
            iconService: GroupIconService(iconsDirectoryURL: iconsDirectory),
            iconCleanupService: GroupIconCleanupService(iconsDirectoryURL: iconsDirectory)
        )

        XCTAssertNil(store.createGroup(named: "   "))
        XCTAssertTrue(store.groups.isEmpty)
    }

    func testCreateGroupReturnsNewGroupID() throws {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsStoreCreateIDTests-\(UUID().uuidString)", isDirectory: true)
        let groupsFileURL = testDirectory.appendingPathComponent("groups.json")
        let iconsDirectory = testDirectory.appendingPathComponent("Icons", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)

        let store = AppGroupStore(
            groupsFileURL: groupsFileURL,
            iconService: GroupIconService(iconsDirectoryURL: iconsDirectory),
            iconCleanupService: GroupIconCleanupService(iconsDirectoryURL: iconsDirectory)
        )

        _ = store.createGroup(named: "First")
        let id = try XCTUnwrap(store.createGroup(named: "Second"))

        XCTAssertEqual(id, store.groups.last?.id)
        XCTAssertEqual(store.groups.last?.name, "Second")
    }

    func testActivationResultsAreTaggedWithGroupID() async throws {
        let group = AppGroup(
            name: "Design",
            apps: [
                GroupedApp(bundleIdentifier: "com.example.Design", name: "Design", appPath: nil)
            ],
            iconFileName: "existing-icon.icns"
        )
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsStoreActivationTagTests-\(UUID().uuidString)", isDirectory: true)
        let groupsFileURL = testDirectory.appendingPathComponent("groups.json")
        defer {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode([group]).write(to: groupsFileURL, options: .atomic)
        let store = AppGroupStore(
            groupsFileURL: groupsFileURL,
            activationService: StubAppActivationService()
        )

        XCTAssertNil(store.lastActivationGroupID)

        await store.activate(groupID: group.id)

        XCTAssertEqual(store.lastActivationGroupID, group.id)
        XCTAssertEqual(store.lastActivationResults.count, 1)
    }

    func testLauncherGenerationResultIsTaggedWithGroupID() throws {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsStoreLauncherTagTests-\(UUID().uuidString)", isDirectory: true)
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

        let store = AppGroupStore(
            groupsFileURL: groupsFileURL,
            launcherGeneratorService: LauncherAppGeneratorService(
                launcherRuntimeExecutableURL: runtimeExecutableURL,
                defaultDestinationDirectory: launchersDirectory
            )
        )
        store.createGroup(named: "Dev")
        let group = try XCTUnwrap(store.groups.first)

        store.generateLauncher(for: group.id)

        XCTAssertNotNil(store.lastLauncherGenerationResult)
        XCTAssertEqual(store.lastLauncherGenerationGroupID, group.id)
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
