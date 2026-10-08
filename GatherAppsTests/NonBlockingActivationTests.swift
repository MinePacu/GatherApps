import Foundation
import XCTest
@testable import GatherApps

@MainActor
final class NonBlockingActivationTests: XCTestCase {
    private var testDirectory: URL!

    override func setUpWithError() throws {
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsNonBlockingActivationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: testDirectory)
    }

    func testMainActorRunsOtherWorkWhileStoreActivationIsSuspended() async throws {
        let gate = ActivationGate()
        let service = RecordingActivationService { await gate.pass() }
        let store = try makeStore(groups: [("Work", ["Editor"])], activationService: service)
        let groupID = try XCTUnwrap(store.groups.first?.id)
        let log = EventLog()

        let activation = Task {
            await store.activate(groupID: groupID)
            log.record("activation finished")
        }
        await gate.waitForArrival()

        let otherTask = Task { log.record("other main actor task ran") }
        await otherTask.value

        XCTAssertEqual(log.events, ["other main actor task ran"])
        XCTAssertNil(store.lastActivationGroupID)

        gate.open()
        await activation.value

        XCTAssertEqual(log.events, ["other main actor task ran", "activation finished"])
        XCTAssertEqual(service.events, ["start Editor", "end Editor"])
        XCTAssertEqual(store.lastActivationGroupID, groupID)
        XCTAssertEqual(store.lastActivationResults, [.success(appName: "Editor")])
    }

    func testOverlappingStoreActivationsRunOneAfterAnother() async throws {
        let gate = ActivationGate()
        let service = RecordingActivationService { await gate.pass() }
        let store = try makeStore(
            groups: [("First", ["A1", "A2"]), ("Second", ["B1", "B2"])],
            activationService: service
        )
        let firstID = store.groups[0].id
        let secondID = store.groups[1].id

        let firstActivation = Task { await store.activate(groupID: firstID) }
        // The first group's first app is now suspended inside the activation service.
        await gate.waitForArrival()
        let secondActivation = Task { await store.activate(groupID: secondID) }
        // Let the second request run up to the point where it waits for the first one.
        let marker = Task {}
        await marker.value

        XCTAssertEqual(service.events, ["start A2"])

        gate.open()
        await firstActivation.value
        await secondActivation.value

        // Each group is activated back-to-front, and the second group starts only after the first ends.
        XCTAssertEqual(service.events, [
            "start A2", "end A2", "start A1", "end A1",
            "start B2", "end B2", "start B1", "end B1"
        ])
        XCTAssertEqual(store.lastActivationGroupID, secondID)
        XCTAssertEqual(store.lastActivationResults, [.success(appName: "B1"), .success(appName: "B2")])
    }

    func testHelperClientTimesOutPromptlyWithoutBlockingMainActor() async {
        // No helper answers for this bundle path, so every request runs into its timeout.
        let missingHelperURL = testDirectory.appendingPathComponent("MissingHelper.app", isDirectory: true)
        let shortClient = NotificationWindowHelperClient(timeout: 0.05, expectedHelperURL: missingHelperURL)
        let longClient = NotificationWindowHelperClient(timeout: 0.3, expectedHelperURL: missingHelperURL)
        let log = EventLog()
        let startDate = Date()

        // Queued before the short request starts, so it can only run once the request suspends.
        // It starts a longer request: a waiting loop that spun the run loop would nest that request
        // and could not return before it, while a suspended wait finishes on its own deadline.
        let otherTask = Task {
            log.record("other main actor task ran")
            _ = await longClient.probe()
            log.record("long request finished")
        }

        let result = await shortClient.raiseWindows(bundleIdentifier: "com.example.NoSuchApp")
        let elapsed = Date().timeIntervalSince(startDate)
        log.record("short request finished")
        await otherTask.value

        XCTAssertEqual(
            result,
            .helperUnavailable(reason: L10n.string("activation.reason.helperDidNotRespond"))
        )
        XCTAssertLessThan(elapsed, 1)
        XCTAssertEqual(log.events, [
            "other main actor task ran",
            "short request finished",
            "long request finished"
        ])
    }

    private func makeStore(
        groups groupSpecs: [(name: String, appNames: [String])],
        activationService: AppActivationProviding
    ) throws -> AppGroupStore {
        let groupsFileURL = testDirectory.appendingPathComponent("groups.json")
        let iconsDirectory = testDirectory.appendingPathComponent("Icons", isDirectory: true)
        let launchersDirectory = testDirectory.appendingPathComponent("Launchers", isDirectory: true)
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)

        let groups = try groupSpecs.map { spec -> AppGroup in
            let iconFileName = "\(spec.name).png"
            try Data(spec.name.utf8).write(to: iconsDirectory.appendingPathComponent(iconFileName))
            return AppGroup(
                name: spec.name,
                apps: spec.appNames.map {
                    GroupedApp(bundleIdentifier: "com.example.\($0)", name: $0, appPath: nil)
                },
                iconFileName: iconFileName
            )
        }
        try JSONEncoder().encode(groups).write(to: groupsFileURL, options: .atomic)

        let iconService = GroupIconService(iconsDirectoryURL: iconsDirectory)
        return AppGroupStore(
            groupsFileURL: groupsFileURL,
            iconService: iconService,
            iconCleanupService: GroupIconCleanupService(iconsDirectoryURL: iconsDirectory),
            activationService: activationService,
            launcherGeneratorService: LauncherAppGeneratorService(
                iconService: iconService,
                launcherRuntimeExecutableURL: nil,
                defaultDestinationDirectory: launchersDirectory
            )
        )
    }
}

@MainActor
private final class EventLog {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

/// Holds every caller of `pass()` until the test opens it, and lets the test wait for the first caller.
@MainActor
private final class ActivationGate {
    private var isOpen = false
    private var hasArrival = false
    private var heldCallers: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        hasArrival = true
        arrivalWaiters.forEach { $0.resume() }
        arrivalWaiters.removeAll()
        guard !isOpen else { return }
        await withCheckedContinuation { heldCallers.append($0) }
    }

    func waitForArrival() async {
        guard !hasArrival else { return }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    func open() {
        isOpen = true
        heldCallers.forEach { $0.resume() }
        heldCallers.removeAll()
    }
}

/// Records when each app activation starts and ends, suspending in between.
@MainActor
private final class RecordingActivationService: AppActivationProviding {
    private(set) var events: [String] = []
    private let suspension: @MainActor () async -> Void

    init(suspension: @escaping @MainActor () async -> Void) {
        self.suspension = suspension
    }

    func activate(_ app: GroupedApp) async -> ActivationResult {
        events.append("start \(app.name)")
        await suspension()
        events.append("end \(app.name)")
        return .success(appName: app.name)
    }

    func activate(bundleIdentifier: String) async -> ActivationResult {
        .success(appName: bundleIdentifier)
    }
}
