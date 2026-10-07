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
}
