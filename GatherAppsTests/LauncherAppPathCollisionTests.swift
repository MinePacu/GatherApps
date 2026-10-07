import XCTest
@testable import GatherApps

@MainActor
final class LauncherAppPathCollisionTests: XCTestCase {
    func testGroupsWithSameNameGetSeparateLaunchers() throws {
        let destination = makeDestination()
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        let generator = try makeGenerator(destination: destination)
        let first = AppGroup(name: "Work")
        let second = AppGroup(name: "Work")

        let firstResult = try generator.generateLauncher(for: first, destinationDirectory: destination)
        let secondResult = try generator.generateLauncher(for: second, destinationDirectory: destination)

        XCTAssertNotEqual(firstResult.appURL, secondResult.appURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstResult.appURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondResult.appURL.path))
        XCTAssertEqual(try groupID(at: firstResult.appURL), first.id.uuidString)
        XCTAssertEqual(try groupID(at: secondResult.appURL), second.id.uuidString)
        XCTAssertEqual(firstResult.appURL.lastPathComponent, "GatherApps - Work.app")
        XCTAssertTrue(
            secondResult.appURL.lastPathComponent.hasSuffix(" (\(second.id.uuidString.prefix(8))).app")
        )
    }

    func testGroupsWhoseNamesSanitizeIdenticallyGetSeparateLaunchers() throws {
        let destination = makeDestination()
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        let generator = try makeGenerator(destination: destination)
        let first = AppGroup(name: "a/b")
        let second = AppGroup(name: "a-b")

        let firstResult = try generator.generateLauncher(for: first, destinationDirectory: destination)
        let secondResult = try generator.generateLauncher(for: second, destinationDirectory: destination)

        XCTAssertNotEqual(firstResult.appURL, secondResult.appURL)
        XCTAssertEqual(try groupID(at: firstResult.appURL), first.id.uuidString)
        XCTAssertEqual(try groupID(at: secondResult.appURL), second.id.uuidString)
    }

    func testDeletingLauncherDoesNotDeleteAnotherGroupsLauncher() throws {
        let destination = makeDestination()
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        let generator = try makeGenerator(destination: destination)

        let first = AppGroup(name: "Work")
        let second = AppGroup(name: "Work")
        let firstURL = try generator.generateLauncher(for: first, destinationDirectory: destination).appURL
        let secondURL = try generator.generateLauncher(for: second, destinationDirectory: destination).appURL

        try generator.deleteLauncher(for: first, destinationDirectory: destination)

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertEqual(try groupID(at: secondURL), second.id.uuidString)

        let reversedDestination = destination.appendingPathComponent("Reversed", isDirectory: true)
        let third = AppGroup(name: "Work")
        let fourth = AppGroup(name: "Work")
        let thirdURL = try generator.generateLauncher(for: third, destinationDirectory: reversedDestination).appURL
        let fourthURL = try generator.generateLauncher(for: fourth, destinationDirectory: reversedDestination).appURL

        try generator.deleteLauncher(for: fourth, destinationDirectory: reversedDestination)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fourthURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: thirdURL.path))
        XCTAssertEqual(try groupID(at: thirdURL), third.id.uuidString)
    }

    func testLauncherPathStaysStableAfterCollidingGroupIsDeleted() throws {
        let destination = makeDestination()
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        let generator = try makeGenerator(destination: destination)
        let first = AppGroup(name: "Work")
        let second = AppGroup(name: "Work")
        let firstURL = try generator.generateLauncher(for: first, destinationDirectory: destination).appURL
        let secondURL = try generator.generateLauncher(for: second, destinationDirectory: destination).appURL

        try generator.deleteLauncher(for: first, destinationDirectory: destination)

        XCTAssertEqual(try generator.launcherURL(for: second, destinationDirectory: destination), secondURL)

        let third = AppGroup(name: "Work")
        let thirdURL = try generator.generateLauncher(for: third, destinationDirectory: destination).appURL

        XCTAssertEqual(thirdURL, firstURL)
        XCTAssertEqual(try groupID(at: thirdURL), third.id.uuidString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertEqual(try groupID(at: secondURL), second.id.uuidString)
    }

    func testDeleteLauncherSkipsBundleWithoutMatchingGroupID() throws {
        let destination = makeDestination()
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        let generator = try makeGenerator(destination: destination)
        let group = AppGroup(name: "Work")
        let baseURL = destination.appendingPathComponent("GatherApps - Work.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: baseURL.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )

        try generator.deleteLauncher(for: group, destinationDirectory: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: baseURL.path))

        let info: [String: Any] = ["GatherAppsGroupID": UUID().uuidString]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: baseURL.appendingPathComponent("Contents/Info.plist"), options: .atomic)

        try generator.deleteLauncher(for: group, destinationDirectory: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: baseURL.path))
    }

    func testRegeneratingStaleLauncherDoesNotTouchAnotherGroupsLauncher() throws {
        let first = AppGroup(name: "Work")
        let second = AppGroup(name: "Work")
        let lifecycleManager = StubLauncherAppLifecycleManager(
            runningBundleIdentifiers: [LauncherTestSupport.launcherBundleIdentifier(for: first)]
        )
        let destination = makeDestination()
        defer {
            try? FileManager.default.removeItem(at: destination)
        }
        let generator = try makeGenerator(destination: destination, lifecycleManager: lifecycleManager)
        let firstURL = try generator.generateLauncher(for: first, destinationDirectory: destination).appURL
        let infoPlistURL = firstURL.appendingPathComponent("Contents/Info.plist")
        let originalInfoData = try Data(contentsOf: infoPlistURL)

        let regenerated = try generator.regenerateLauncherIfStale(for: second, destinationDirectory: destination)

        XCTAssertFalse(regenerated)
        XCTAssertEqual(try Data(contentsOf: infoPlistURL), originalInfoData)
        XCTAssertEqual(try groupID(at: firstURL), first.id.uuidString)
        XCTAssertTrue(lifecycleManager.events.isEmpty)
    }

    private func makeDestination() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsLauncherCollisionTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeGenerator(
        destination: URL,
        lifecycleManager: LauncherAppLifecycleManaging = StubLauncherAppLifecycleManager()
    ) throws -> LauncherAppGeneratorService {
        let runtimeExecutableURL = destination
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        try LauncherTestSupport.writeRuntimeExecutable(named: "runtime executable", to: runtimeExecutableURL)
        return LauncherAppGeneratorService(
            launcherRuntimeExecutableURL: runtimeExecutableURL,
            launcherAppLifecycleManager: lifecycleManager
        )
    }

    private func groupID(at appURL: URL) throws -> String? {
        try LauncherTestSupport.infoPlist(at: appURL)["GatherAppsGroupID"] as? String
    }
}
