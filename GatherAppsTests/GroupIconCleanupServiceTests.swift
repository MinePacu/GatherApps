import XCTest
@testable import GatherApps

@MainActor
final class GroupIconCleanupServiceTests: XCTestCase {
    func testCleanupRemovesOnlyUnreferencedPNGFiles() throws {
        let iconsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsGroupIconCleanup-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: iconsDirectory)
        }
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)

        let referencedURL = iconsDirectory.appendingPathComponent("referenced.png")
        let orphanedURL = iconsDirectory.appendingPathComponent("orphaned.png")
        let unrelatedURL = iconsDirectory.appendingPathComponent("note.txt")

        try Data("keep".utf8).write(to: referencedURL)
        try Data("delete".utf8).write(to: orphanedURL)
        try Data("ignore".utf8).write(to: unrelatedURL)

        let cleanupService = GroupIconCleanupService(iconsDirectoryURL: iconsDirectory)

        try cleanupService.cleanup(referencedFileNames: ["referenced.png"])

        XCTAssertTrue(FileManager.default.fileExists(atPath: referencedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedURL.path))
    }
}
