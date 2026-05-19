import XCTest
@testable import GatherApps

enum LauncherTestSupport {
    struct StoreRefreshFixture {
        let testDirectory: URL
        let groupsFileURL: URL
        let launchersDirectory: URL
        let oldRuntimeExecutableURL: URL
        let currentRuntimeExecutableURL: URL
        let currentRuntimeContents: Data
    }

    static func makeStoreRefreshFixture() throws -> StoreRefreshFixture {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsStoreLauncherRefreshTests-\(UUID().uuidString)", isDirectory: true)
        let oldRuntimeExecutableURL = testDirectory
            .appendingPathComponent("OldRuntime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
        let currentRuntimeExecutableURL = testDirectory
            .appendingPathComponent("CurrentRuntime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")

        try createDirectories(for: oldRuntimeExecutableURL, currentRuntimeExecutableURL)
        try writeRuntimeExecutable(named: "old runtime", to: oldRuntimeExecutableURL)
        let currentRuntimeContents = try writeRuntimeExecutable(
            named: "current runtime",
            to: currentRuntimeExecutableURL
        )

        return StoreRefreshFixture(
            testDirectory: testDirectory,
            groupsFileURL: testDirectory.appendingPathComponent("groups.json"),
            launchersDirectory: testDirectory.appendingPathComponent("Launchers", isDirectory: true),
            oldRuntimeExecutableURL: oldRuntimeExecutableURL,
            currentRuntimeExecutableURL: currentRuntimeExecutableURL,
            currentRuntimeContents: currentRuntimeContents
        )
    }

    static func createDirectories(for urls: URL...) throws {
        for url in urls {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
    }

    static func infoPlist(at appURL: URL) throws -> [String: Any] {
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let infoData = try Data(contentsOf: infoPlistURL)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        )
    }

    @discardableResult
    static func writeRuntimeExecutable(named name: String, to url: URL) throws -> Data {
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

    static func runtimeFixtureURL(named name: String) -> URL {
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

    static func launcherBundleIdentifier(for group: AppGroup) -> String {
        "com.minepacu.GatherApps.launcher.\(group.id.uuidString.lowercased())"
    }
}

final class StubLauncherAppLifecycleManager: LauncherAppLifecycleManaging {
    enum Event: Equatable {
        case checkedRunning(String)
        case terminated(String)
        case forceTerminated(String)
        case launched(URL)
    }

    private let runningBundleIdentifiers: Set<String>
    private let gracefulTerminationSucceeds: Bool
    private(set) var events: [Event] = []

    init(
        runningBundleIdentifiers: Set<String> = [],
        gracefulTerminationSucceeds: Bool = true
    ) {
        self.runningBundleIdentifiers = runningBundleIdentifiers
        self.gracefulTerminationSucceeds = gracefulTerminationSucceeds
    }

    func isLauncherRunning(bundleIdentifier: String) -> Bool {
        events.append(.checkedRunning(bundleIdentifier))
        return runningBundleIdentifiers.contains(bundleIdentifier)
    }

    func terminateLauncher(bundleIdentifier: String) -> Bool {
        events.append(.terminated(bundleIdentifier))
        return gracefulTerminationSucceeds
    }

    func forceTerminateLauncher(bundleIdentifier: String) {
        events.append(.forceTerminated(bundleIdentifier))
    }

    func launchLauncher(at appURL: URL) {
        events.append(.launched(appURL))
    }
}
