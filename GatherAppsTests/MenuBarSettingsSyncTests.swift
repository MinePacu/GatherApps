import AppKit
import Foundation
import ServiceManagement
import XCTest
@testable import GatherApps

@MainActor
final class MenuBarSettingsSyncTests: XCTestCase {
    func testStartStatusBarAppliesAccessoryPolicyWhenDockIconIsHidden() throws {
        var policies: [NSApplication.ActivationPolicy] = []
        let coordinator = try makeCoordinator(
            settings: makeSettings(showsStatusBarItem: true, showsDockIcon: false),
            setActivationPolicy: { policies.append($0) }
        )

        coordinator.startStatusBar()

        XCTAssertEqual(policies, [.accessory])
    }

    func testStartStatusBarRestoresDockIconWhenBothEntryPointsAreHidden() throws {
        var policies: [NSApplication.ActivationPolicy] = []
        let settings = try makeSettings(showsStatusBarItem: false, showsDockIcon: false)
        let coordinator = try makeCoordinator(
            settings: settings,
            setActivationPolicy: { policies.append($0) }
        )

        coordinator.startStatusBar()

        XCTAssertTrue(settings.showsDockIcon)
        XCTAssertEqual(policies, [.regular])
    }

    func testOpeningMenuClearsLaunchAtLoginWhenSystemItemIsNotRegistered() throws {
        let settings = try makeSettings()
        settings.launchesAtLogin = true
        let controller = try makeController(settings: settings, loginItemStatus: { .notRegistered })

        controller.menuNeedsUpdate(controller.statusMenu)

        XCTAssertFalse(settings.launchesAtLogin)
        XCTAssertEqual(try launchAtLoginItem(in: controller).state, .off)
    }

    func testOpeningMenuChecksLaunchAtLoginWhenSystemItemIsEnabled() throws {
        let settings = try makeSettings()
        settings.launchesAtLogin = false
        let controller = try makeController(settings: settings, loginItemStatus: { .enabled })

        controller.menuNeedsUpdate(controller.statusMenu)

        XCTAssertTrue(settings.launchesAtLogin)
        XCTAssertEqual(try launchAtLoginItem(in: controller).state, .on)
    }

    func testTogglingLaunchAtLoginKeepsFlagWhenRegistrationSucceeds() throws {
        let settings = try makeSettings()
        var status = SMAppService.Status.notRegistered
        var registerCallCount = 0
        let controller = try makeController(
            settings: settings,
            loginItemStatus: { status },
            register: {
                registerCallCount += 1
                status = .enabled
            }
        )

        controller.toggleLaunchAtLogin()

        XCTAssertEqual(registerCallCount, 1)
        XCTAssertTrue(settings.launchesAtLogin)
    }

    func testTogglingLaunchAtLoginRevertsFlagAndReportsErrorWhenRegistrationFails() throws {
        let settings = try makeSettings()
        let store = try makeStore()
        let controller = try makeController(
            settings: settings,
            store: store,
            loginItemStatus: { .notRegistered },
            register: { throw StubLoginItemError.failed }
        )

        controller.toggleLaunchAtLogin()

        XCTAssertFalse(settings.launchesAtLogin)
        XCTAssertNotNil(store.lastErrorMessage)
    }

    private enum StubLoginItemError: Error {
        case failed
    }

    private func launchAtLoginItem(in controller: StatusBarController) throws -> NSMenuItem {
        let title = L10n.string("statusBar.launchAtLogin")
        return try XCTUnwrap(controller.statusMenu.items.first { $0.title == title })
    }

    private func makeSettings(showsStatusBarItem: Bool = true, showsDockIcon: Bool = true) throws -> MenuBarSettings {
        let defaultsSuiteName = "GatherAppsMenuBarSettingsSyncTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        addTeardownBlock {
            UserDefaults().removePersistentDomain(forName: defaultsSuiteName)
        }
        let settings = MenuBarSettings(defaults: defaults)
        settings.showsStatusBarItem = showsStatusBarItem
        settings.showsDockIcon = showsDockIcon
        return settings
    }

    private func makeStore() throws -> AppGroupStore {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsMenuBarSettingsSyncTests-\(UUID().uuidString)", isDirectory: true)
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

    private func makeCoordinator(
        settings: MenuBarSettings,
        setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Void
    ) throws -> GatherAppsAppCoordinator {
        GatherAppsAppCoordinator(
            store: try makeStore(),
            settings: settings,
            showSwitcherAction: { _ in },
            activateAppAction: {},
            setActivationPolicy: setActivationPolicy
        )
    }

    private func makeController(
        settings: MenuBarSettings,
        store: AppGroupStore? = nil,
        loginItemStatus: @escaping () -> SMAppService.Status,
        register: @escaping () throws -> Void = {},
        unregister: @escaping () throws -> Void = {}
    ) throws -> StatusBarController {
        StatusBarController(
            store: try store ?? makeStore(),
            settings: settings,
            actions: StatusBarActions(
                activateGroup: { _ in },
                showSwitcher: {},
                showMainWindow: {}
            ),
            runningAppProvider: { [] },
            windowHelperServiceStatusProvider: { .enabled },
            mainAppLoginItemStatusProvider: loginItemStatus,
            registerMainAppLoginItem: register,
            unregisterMainAppLoginItem: unregister,
            setActivationPolicy: { _ in },
            openURL: { _ in }
        )
    }
}
