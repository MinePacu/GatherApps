import AppKit
import Foundation
import ServiceManagement
import XCTest
@testable import GatherApps

@MainActor
final class AccessibilityPermissionWarningTests: XCTestCase {
    private var testDirectory: URL!

    override func setUpWithError() throws {
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsAccessibilityWarningTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: testDirectory)
    }

    func testActivationResultsSetAndClearWarning() async throws {
        let activationService = StubWarningActivationService()
        let store = try makeStore(activationService: activationService)
        let groupID = try XCTUnwrap(store.groups.first?.id)
        XCTAssertFalse(store.needsAccessibilityPermission)

        activationService.results = [
            .success(appName: "First"),
            .accessibilityPermissionMissing(appName: "Second")
        ]
        await store.activate(groupID: groupID)
        XCTAssertTrue(store.needsAccessibilityPermission)

        activationService.results = [
            .appNotRunning(bundleIdentifier: "com.example.first"),
            .appNotRunning(bundleIdentifier: "com.example.second")
        ]
        await store.activate(groupID: groupID)
        XCTAssertTrue(store.needsAccessibilityPermission)

        activationService.results = [
            .success(appName: "First"),
            .appNotRunning(bundleIdentifier: "com.example.second")
        ]
        await store.activate(groupID: groupID)
        XCTAssertFalse(store.needsAccessibilityPermission)
    }

    func testStatusMenuShowsWarningItemOnlyWhenPermissionIsNeeded() async throws {
        let activationService = StubWarningActivationService()
        let store = try makeStore(activationService: activationService)
        let controller = try makeController(store: store, client: StubWarningWindowHelperClient())
        let warningTitle = L10n.string("statusBar.accessibilityWarning.menuItem")

        controller.menuNeedsUpdate(controller.statusMenu)
        XCTAssertFalse(controller.statusMenu.items.contains { $0.title == warningTitle })

        try await activateWithPermissionMissing(store: store, activationService: activationService)
        controller.menuNeedsUpdate(controller.statusMenu)

        let warningItem = controller.statusMenu.items[1]
        XCTAssertEqual(warningItem.title, warningTitle)
        XCTAssertTrue(warningItem.isEnabled)
        XCTAssertTrue(warningItem.target === controller)
        XCTAssertEqual(warningItem.action, #selector(StatusBarController.requestAccessibilityPermission))
    }

    func testStatusSymbolNameReflectsWarning() {
        XCTAssertEqual(StatusBarController.statusSymbolName(showsAccessibilityWarning: false), "square.grid.2x2")
        XCTAssertEqual(
            StatusBarController.statusSymbolName(showsAccessibilityWarning: true),
            "exclamationmark.triangle"
        )
    }

    func testOpeningWindowRaisingMenuClearsWarningWhenHelperIsTrusted() async throws {
        let activationService = StubWarningActivationService()
        let store = try makeStore(activationService: activationService)
        let client = StubWarningWindowHelperClient(probeRuntimeInfo: Self.runtimeInfo(accessibilityTrusted: true))
        let controller = try makeController(store: store, client: client)
        try await activateWithPermissionMissing(store: store, activationService: activationService)

        _ = try XCTUnwrap(windowRaisingSubmenu(in: controller.makeMenu()))
        await controller.updateWindowRaisingStatus()

        XCTAssertFalse(store.needsAccessibilityPermission)
    }

    func testOpeningWindowRaisingMenuKeepsWarningWhenHelperIsNotTrusted() async throws {
        let activationService = StubWarningActivationService()
        let store = try makeStore(activationService: activationService)
        let client = StubWarningWindowHelperClient(probeRuntimeInfo: Self.runtimeInfo(accessibilityTrusted: false))
        let controller = try makeController(store: store, client: client)
        try await activateWithPermissionMissing(store: store, activationService: activationService)

        _ = try XCTUnwrap(windowRaisingSubmenu(in: controller.makeMenu()))
        await controller.updateWindowRaisingStatus()

        XCTAssertTrue(store.needsAccessibilityPermission)
    }

    func testRequestingPermissionClearsWarningWhenHelperReportsTrusted() async throws {
        let activationService = StubWarningActivationService()
        let store = try makeStore(activationService: activationService)
        let client = StubWarningWindowHelperClient(
            requestRuntimeInfo: Self.runtimeInfo(accessibilityTrusted: true)
        )
        let controller = try makeController(store: store, client: client)
        try await activateWithPermissionMissing(store: store, activationService: activationService)

        await controller.performAccessibilityPermissionRequest()

        XCTAssertFalse(store.needsAccessibilityPermission)
    }

    private func activateWithPermissionMissing(
        store: AppGroupStore,
        activationService: StubWarningActivationService
    ) async throws {
        activationService.results = [.accessibilityPermissionMissing(appName: "First")]
        let groupID = try XCTUnwrap(store.groups.first?.id)
        await store.activate(groupID: groupID)
        XCTAssertTrue(store.needsAccessibilityPermission)
    }

    private static func runtimeInfo(accessibilityTrusted: Bool) -> WindowHelperRuntimeInfo {
        WindowHelperRuntimeInfo(
            bundleURL: URL(fileURLWithPath: "/Applications/GatherApps.app/Contents/Library/LoginItems/Helper.app"),
            protocolVersion: WindowHelperConfiguration.protocolVersion,
            accessibilityTrusted: accessibilityTrusted
        )
    }

    private func makeStore(activationService: StubWarningActivationService) throws -> AppGroupStore {
        let groupsFileURL = testDirectory.appendingPathComponent("groups.json")
        let iconsDirectory = testDirectory.appendingPathComponent("Icons", isDirectory: true)
        let launchersDirectory = testDirectory.appendingPathComponent("Launchers", isDirectory: true)
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)

        let iconFileName = "Group.png"
        try Data("Group".utf8).write(to: iconsDirectory.appendingPathComponent(iconFileName))
        let group = AppGroup(
            name: "Group",
            apps: [
                GroupedApp(bundleIdentifier: "com.example.first", name: "First", appPath: nil),
                GroupedApp(bundleIdentifier: "com.example.second", name: "Second", appPath: nil)
            ],
            iconFileName: iconFileName
        )
        try JSONEncoder().encode([group]).write(to: groupsFileURL, options: .atomic)

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

    private func makeController(
        store: AppGroupStore,
        client: StubWarningWindowHelperClient
    ) throws -> StatusBarController {
        let defaultsSuiteName = "GatherAppsAccessibilityWarningTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        addTeardownBlock {
            UserDefaults().removePersistentDomain(forName: defaultsSuiteName)
        }
        return StatusBarController(
            store: store,
            settings: MenuBarSettings(defaults: defaults),
            actions: StatusBarActions(
                activateGroup: { _ in },
                showSwitcher: {},
                showMainWindow: {}
            ),
            runningAppProvider: { [] },
            windowHelperRegistrationService: StubWarningRegistrationService(),
            windowHelperClient: client,
            windowHelperServiceStatusProvider: { .enabled },
            setActivationPolicy: { _ in },
            openURL: { _ in }
        )
    }

    private func windowRaisingSubmenu(in menu: NSMenu) -> NSMenu? {
        menu.items.first { $0.title == L10n.string("statusBar.windowRaising") }?.submenu
    }
}

private final class StubWarningActivationService: AppActivationProviding {
    var results: [ActivationResult] = []

    func activate(_ app: GroupedApp) async -> ActivationResult {
        .success(appName: app.name)
    }

    func activate(bundleIdentifier: String) async -> ActivationResult {
        .success(appName: bundleIdentifier)
    }

    func activateGroup(_ apps: [GroupedApp]) async -> [ActivationResult] {
        results
    }
}

private final class StubWarningRegistrationService: WindowHelperRegistrationProviding {
    func ensureRegistered() async -> WindowHelperRegistrationResult {
        .available
    }
}

private final class StubWarningWindowHelperClient: WindowHelperClient {
    let probeRuntimeInfo: WindowHelperRuntimeInfo?
    let requestRuntimeInfo: WindowHelperRuntimeInfo?

    init(probeRuntimeInfo: WindowHelperRuntimeInfo? = nil, requestRuntimeInfo: WindowHelperRuntimeInfo? = nil) {
        self.probeRuntimeInfo = probeRuntimeInfo
        self.requestRuntimeInfo = requestRuntimeInfo
    }

    func raiseWindows(bundleIdentifier: String) async -> WindowHelperActivationResult {
        .helperUnavailable(reason: "unused")
    }

    func probe() async -> WindowHelperRuntimeInfo? {
        probeRuntimeInfo
    }

    func requestAccessibilityPermission() async -> WindowHelperRuntimeInfo? {
        requestRuntimeInfo
    }
}
