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

        XCTAssertEqual(StatusBarAccessibilityStatus.title(runtimeInfo: nil), "Unavailable")
        XCTAssertEqual(
            StatusBarAccessibilityStatus.title(runtimeInfo: WindowHelperRuntimeInfo(
                bundleURL: helperURL,
                protocolVersion: WindowHelperConfiguration.protocolVersion,
                accessibilityTrusted: false
            )),
            "Needs Permission"
        )
        XCTAssertEqual(
            StatusBarAccessibilityStatus.title(runtimeInfo: WindowHelperRuntimeInfo(
                bundleURL: helperURL,
                protocolVersion: WindowHelperConfiguration.protocolVersion,
                accessibilityTrusted: true
            )),
            "Granted"
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
        XCTAssertEqual(submenu?.items.first?.title, "Helper: Checking...")
        XCTAssertEqual(submenu?.items.dropFirst().first?.title, "Accessibility: Checking...")
    }

    @MainActor
    func testOpeningWindowRaisingMenuProbesHelperOnceAndUpdatesStatus() throws {
        let registrationService = StubStatusBarRegistrationService()
        let client = StubStatusBarWindowHelperClient(runtimeInfo: WindowHelperRuntimeInfo(
            bundleURL: URL(fileURLWithPath: "/Applications/GatherApps.app/Contents/Library/LoginItems/Helper.app"),
            protocolVersion: WindowHelperConfiguration.protocolVersion,
            accessibilityTrusted: true
        ))
        let controller = try makeController(registrationService: registrationService, client: client)
        let menu = controller.makeMenu()
        let submenu = try XCTUnwrap(windowRaisingSubmenu(in: menu))

        controller.menuNeedsUpdate(submenu)

        XCTAssertEqual(client.probeCallCount, 1)
        XCTAssertEqual(registrationService.ensureRegisteredCallCount, 0)
        XCTAssertEqual(submenu.items[0].title, "Helper: Running")
        XCTAssertEqual(submenu.items[1].title, "Accessibility: Granted")
    }

    @MainActor
    func testOpeningWindowRaisingMenuShowsUnavailableWhenHelperDoesNotRespond() throws {
        let registrationService = StubStatusBarRegistrationService()
        let client = StubStatusBarWindowHelperClient(runtimeInfo: nil)
        let controller = try makeController(registrationService: registrationService, client: client)
        let menu = controller.makeMenu()
        let submenu = try XCTUnwrap(windowRaisingSubmenu(in: menu))

        controller.menuNeedsUpdate(submenu)

        XCTAssertEqual(client.probeCallCount, 1)
        XCTAssertEqual(registrationService.ensureRegisteredCallCount, 0)
        XCTAssertEqual(submenu.items[0].title, "Helper: Not Running")
        XCTAssertEqual(submenu.items[1].title, "Accessibility: Unavailable")
    }

    @MainActor
    private func makeController(
        registrationService: StubStatusBarRegistrationService,
        client: StubStatusBarWindowHelperClient
    ) throws -> StatusBarController {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsStatusBarTests-\(UUID().uuidString)", isDirectory: true)
        let iconsDirectory = testDirectory.appendingPathComponent("Icons", isDirectory: true)
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: testDirectory)
        }

        let defaultsSuiteName = "GatherAppsStatusBarTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        addTeardownBlock {
            UserDefaults().removePersistentDomain(forName: defaultsSuiteName)
        }

        let store = AppGroupStore(
            groupsFileURL: testDirectory.appendingPathComponent("groups.json"),
            iconService: GroupIconService(iconsDirectoryURL: iconsDirectory),
            iconCleanupService: GroupIconCleanupService(iconsDirectoryURL: iconsDirectory)
        )
        return StatusBarController(
            store: store,
            settings: MenuBarSettings(defaults: defaults),
            actions: StatusBarActions(
                activateGroup: { _ in },
                showSwitcher: {},
                showMainWindow: {}
            ),
            runningAppProvider: { [] },
            windowHelperRegistrationService: registrationService,
            windowHelperClient: client,
            windowHelperServiceStatusProvider: { .enabled }
        )
    }

    @MainActor
    private func windowRaisingSubmenu(in menu: NSMenu) -> NSMenu? {
        menu.items.first { $0.title == "Window Raising" }?.submenu
    }
}

private final class StubStatusBarRegistrationService: WindowHelperRegistrationProviding {
    private(set) var ensureRegisteredCallCount = 0

    func ensureRegistered() -> WindowHelperRegistrationResult {
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

    func raiseWindows(bundleIdentifier: String) -> WindowHelperActivationResult {
        .helperUnavailable(reason: "unused")
    }

    func probe() -> WindowHelperRuntimeInfo? {
        probeCallCount += 1
        return runtimeInfo
    }
}
