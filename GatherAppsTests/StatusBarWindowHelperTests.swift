import AppKit
import Foundation
import ServiceManagement
import XCTest
@testable import GatherApps

final class StatusBarWindowHelperTests: XCTestCase {
    func testAccessibilityStatusUsesHelperRuntimeInformation() {
        let helperURL = URL(
            fileURLWithPath: "/Applications/GatherApps.app/Contents/Library/LoginItems/Helper.app"
        )

        XCTAssertEqual(
            StatusBarAccessibilityStatus.title(runtimeInfo: nil),
            L10n.string("statusBar.accessibility.unavailable")
        )
        XCTAssertEqual(
            StatusBarAccessibilityStatus.title(runtimeInfo: WindowHelperRuntimeInfo(
                bundleURL: helperURL,
                protocolVersion: WindowHelperConfiguration.protocolVersion,
                accessibilityTrusted: false
            )),
            L10n.string("statusBar.accessibility.needsPermission")
        )
        XCTAssertEqual(
            StatusBarAccessibilityStatus.title(runtimeInfo: WindowHelperRuntimeInfo(
                bundleURL: helperURL,
                protocolVersion: WindowHelperConfiguration.protocolVersion,
                accessibilityTrusted: true
            )),
            L10n.string("statusBar.accessibility.granted")
        )
    }

    @MainActor
    func testBuildingMenuDoesNotCheckHelperRegistrationOrProbe() throws {
        let registrationService = StubStatusBarRegistrationService()
        let client = StubStatusBarWindowHelperClient(runtimeInfo: nil)
        let controller = try makeController(registrationService: registrationService, client: client)

        var submenu: NSMenu?
        for _ in 0..<3 {
            submenu = windowRaisingSubmenu(in: controller.makeMenu())
        }

        XCTAssertEqual(registrationService.ensureRegisteredCallCount, 0)
        XCTAssertEqual(client.probeCallCount, 0)
        XCTAssertEqual(submenu?.items.first?.title, L10n.string("statusBar.helper.checking"))
        XCTAssertEqual(
            submenu?.items.dropFirst().first?.title,
            L10n.string("statusBar.accessibility.checking")
        )
    }

    @MainActor
    func testOpeningWindowRaisingMenuProbesHelperOnceAndUpdatesStatus() async throws {
        let registrationService = StubStatusBarRegistrationService()
        let client = StubStatusBarWindowHelperClient(runtimeInfo: WindowHelperRuntimeInfo(
            bundleURL: URL(fileURLWithPath: "/Applications/GatherApps.app/Contents/Library/LoginItems/Helper.app"),
            protocolVersion: WindowHelperConfiguration.protocolVersion,
            accessibilityTrusted: true
        ))
        let controller = try makeController(registrationService: registrationService, client: client)
        let menu = controller.makeMenu()
        let submenu = try XCTUnwrap(windowRaisingSubmenu(in: menu))

        await controller.updateWindowRaisingStatus()

        XCTAssertEqual(client.probeCallCount, 1)
        XCTAssertEqual(registrationService.ensureRegisteredCallCount, 0)
        XCTAssertEqual(
            submenu.items[0].title,
            L10n.format("statusBar.helper.format", L10n.string("statusBar.helper.running"))
        )
        XCTAssertEqual(
            submenu.items[1].title,
            L10n.format("statusBar.accessibility.format", L10n.string("statusBar.accessibility.granted"))
        )
    }

    @MainActor
    func testOpeningWindowRaisingMenuShowsUnavailableWhenHelperDoesNotRespond() async throws {
        let registrationService = StubStatusBarRegistrationService()
        let client = StubStatusBarWindowHelperClient(runtimeInfo: nil)
        let controller = try makeController(registrationService: registrationService, client: client)
        let menu = controller.makeMenu()
        let submenu = try XCTUnwrap(windowRaisingSubmenu(in: menu))

        await controller.updateWindowRaisingStatus()

        XCTAssertEqual(client.probeCallCount, 1)
        XCTAssertEqual(registrationService.ensureRegisteredCallCount, 0)
        XCTAssertEqual(
            submenu.items[0].title,
            L10n.format("statusBar.helper.format", L10n.string("statusBar.helper.notRunning"))
        )
        XCTAssertEqual(
            submenu.items[1].title,
            L10n.format("statusBar.accessibility.format", L10n.string("statusBar.accessibility.unavailable"))
        )
    }

    @MainActor
    func testStatusMenuReflectsGroupCreatedAfterLastRefresh() throws {
        let store = try makeStore()
        let controller = try makeController(
            registrationService: StubStatusBarRegistrationService(),
            client: StubStatusBarWindowHelperClient(runtimeInfo: nil),
            store: store
        )

        controller.menuNeedsUpdate(controller.statusMenu)
        XCTAssertFalse(menuContainsTitle("New Group", in: controller.statusMenu))

        store.createGroup(named: "New Group")
        controller.menuNeedsUpdate(controller.statusMenu)

        XCTAssertTrue(menuContainsTitle("New Group", in: controller.statusMenu))
    }

    @MainActor
    func testStatusMenuRereadsRunningAppsWhenOpened() throws {
        var providerCallCount = 0
        let controller = try makeController(
            registrationService: StubStatusBarRegistrationService(),
            client: StubStatusBarWindowHelperClient(runtimeInfo: nil),
            runningAppProvider: {
                providerCallCount += 1
                return []
            }
        )
        providerCallCount = 0

        controller.menuNeedsUpdate(controller.statusMenu)
        XCTAssertEqual(providerCallCount, 1)
        controller.menuNeedsUpdate(controller.statusMenu)
        XCTAssertEqual(providerCallCount, 2)
    }

    @MainActor
    func testOpeningStatusMenuDoesNotProbeHelper() throws {
        let registrationService = StubStatusBarRegistrationService()
        let client = StubStatusBarWindowHelperClient(runtimeInfo: nil)
        let controller = try makeController(registrationService: registrationService, client: client)

        controller.menuNeedsUpdate(controller.statusMenu)

        XCTAssertEqual(client.probeCallCount, 0)
        XCTAssertEqual(registrationService.ensureRegisteredCallCount, 0)
    }

    @MainActor
    func testHidingStatusItemWhileDockIconHiddenRestoresDockIcon() throws {
        var recordedPolicies: [NSApplication.ActivationPolicy] = []
        let settings = try makeSettings(showsStatusBarItem: true, showsDockIcon: false)
        let controller = try makeController(
            registrationService: StubStatusBarRegistrationService(),
            client: StubStatusBarWindowHelperClient(runtimeInfo: nil),
            settings: settings,
            setActivationPolicy: { recordedPolicies.append($0) }
        )

        controller.toggleStatusBarItem()

        XCTAssertFalse(settings.showsStatusBarItem)
        XCTAssertTrue(settings.showsDockIcon)
        XCTAssertEqual(recordedPolicies, [.regular])
    }

    @MainActor
    func testHidingDockIconWhileStatusItemHiddenIsIgnored() throws {
        var recordedPolicies: [NSApplication.ActivationPolicy] = []
        let settings = try makeSettings(showsStatusBarItem: false, showsDockIcon: true)
        let controller = try makeController(
            registrationService: StubStatusBarRegistrationService(),
            client: StubStatusBarWindowHelperClient(runtimeInfo: nil),
            settings: settings,
            setActivationPolicy: { recordedPolicies.append($0) }
        )

        controller.toggleDockIcon()

        XCTAssertTrue(settings.showsDockIcon)
        XCTAssertFalse(settings.showsStatusBarItem)
        XCTAssertTrue(recordedPolicies.isEmpty)
    }

    @MainActor
    private func makeSettings(showsStatusBarItem: Bool = true, showsDockIcon: Bool = true) throws -> MenuBarSettings {
        let defaultsSuiteName = "GatherAppsStatusBarTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        addTeardownBlock {
            UserDefaults().removePersistentDomain(forName: defaultsSuiteName)
        }
        let settings = MenuBarSettings(defaults: defaults)
        settings.showsStatusBarItem = showsStatusBarItem
        settings.showsDockIcon = showsDockIcon
        return settings
    }

    @MainActor
    private func makeStore() throws -> AppGroupStore {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsStatusBarTests-\(UUID().uuidString)", isDirectory: true)
        let iconsDirectory = testDirectory.appendingPathComponent("Icons", isDirectory: true)
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: testDirectory)
        }

        return AppGroupStore(
            groupsFileURL: testDirectory.appendingPathComponent("groups.json"),
            iconService: GroupIconService(iconsDirectoryURL: iconsDirectory),
            iconCleanupService: GroupIconCleanupService(iconsDirectoryURL: iconsDirectory)
        )
    }

    @MainActor
    private func menuContainsTitle(_ text: String, in menu: NSMenu) -> Bool {
        menu.items.contains { $0.title.contains(text) || ($0.attributedTitle?.string.contains(text) ?? false) }
    }

    @MainActor
    private func makeController(
        registrationService: StubStatusBarRegistrationService,
        client: StubStatusBarWindowHelperClient,
        settings: MenuBarSettings? = nil,
        store: AppGroupStore? = nil,
        runningAppProvider: @escaping () -> [RunningAppInfo] = { [] },
        setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = { _ in }
    ) throws -> StatusBarController {
        let store = try store ?? makeStore()
        return StatusBarController(
            store: store,
            settings: try settings ?? makeSettings(),
            actions: StatusBarActions(
                activateGroup: { _ in },
                showSwitcher: {},
                showMainWindow: {}
            ),
            runningAppProvider: runningAppProvider,
            windowHelperRegistrationService: registrationService,
            windowHelperClient: client,
            windowHelperServiceStatusProvider: { .enabled },
            setActivationPolicy: setActivationPolicy
        )
    }

    @MainActor
    private func windowRaisingSubmenu(in menu: NSMenu) -> NSMenu? {
        menu.items.first { $0.title == L10n.string("statusBar.windowRaising") }?.submenu
    }
}

private final class StubStatusBarRegistrationService: WindowHelperRegistrationProviding {
    private(set) var ensureRegisteredCallCount = 0

    func ensureRegistered() async -> WindowHelperRegistrationResult {
        ensureRegisteredCallCount += 1
        return .available
    }
}

private final class StubStatusBarWindowHelperClient: WindowHelperClient {
    let runtimeInfo: WindowHelperRuntimeInfo?
    private(set) var probeCallCount = 0

    init(runtimeInfo: WindowHelperRuntimeInfo?) {
        self.runtimeInfo = runtimeInfo
    }

    func raiseWindows(bundleIdentifier: String) async -> WindowHelperActivationResult {
        .helperUnavailable(reason: "unused")
    }

    func probe() async -> WindowHelperRuntimeInfo? {
        probeCallCount += 1
        return runtimeInfo
    }
}
