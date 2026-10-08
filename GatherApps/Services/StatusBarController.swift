import AppKit
import ServiceManagement

struct StatusBarActions {
    let activateGroup: (AppGroup.ID) -> Void
    let showSwitcher: () -> Void
    let showMainWindow: () -> Void
}

enum StatusBarWindowHelperStatus {
    static func title(serviceStatus: SMAppService.Status, isHelperRunning: Bool) -> String {
        switch serviceStatus {
        case .enabled:
            return L10n.string(isHelperRunning ? "statusBar.helper.running" : "statusBar.helper.notRunning")
        case .requiresApproval:
            return L10n.string("statusBar.helper.needsApproval")
        case .notRegistered:
            return L10n.string(isHelperRunning ? "statusBar.helper.running" : "statusBar.helper.unavailable")
        case .notFound:
            return L10n.string("statusBar.helper.unavailable")
        @unknown default:
            return L10n.string("statusBar.helper.unavailable")
        }
    }
}

enum StatusBarAccessibilityStatus {
    static func title(runtimeInfo: WindowHelperRuntimeInfo?) -> String {
        guard let runtimeInfo else { return L10n.string("statusBar.accessibility.unavailable") }
        return L10n.string(
            runtimeInfo.accessibilityTrusted
                ? "statusBar.accessibility.granted"
                : "statusBar.accessibility.needsPermission"
        )
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let store: AppGroupStore
    private let settings: MenuBarSettings
    private let actions: StatusBarActions
    private let runningAppProvider: () -> [RunningAppInfo]
    private let windowHelperRegistrationService: WindowHelperRegistrationProviding
    private let windowHelperClient: WindowHelperClient
    private let windowHelperServiceStatusProvider: () -> SMAppService.Status
    private let mainAppLoginItemStatusProvider: () -> SMAppService.Status
    private let registerMainAppLoginItem: () throws -> Void
    private let unregisterMainAppLoginItem: () throws -> Void
    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Void
    private let openURL: (URL) -> Void
    /// Persistent menu attached to the status item. Its contents are rebuilt every time it is about to open
    /// (`menuNeedsUpdate`) because `@Published` sinks fire in `willSet`, before the stores hold the new values.
    let statusMenu = NSMenu(title: "GatherApps")
    private var statusItem: NSStatusItem?
    private weak var windowRaisingMenu: NSMenu?
    private weak var windowHelperStatusItem: NSMenuItem?
    private weak var accessibilityStatusItem: NSMenuItem?

    init(
        store: AppGroupStore,
        settings: MenuBarSettings,
        actions: StatusBarActions,
        runningAppProvider: (() -> [RunningAppInfo])? = nil,
        windowHelperRegistrationService: WindowHelperRegistrationProviding? = nil,
        windowHelperClient: WindowHelperClient? = nil,
        windowHelperServiceStatusProvider: (() -> SMAppService.Status)? = nil,
        mainAppLoginItemStatusProvider: (() -> SMAppService.Status)? = nil,
        registerMainAppLoginItem: (() throws -> Void)? = nil,
        unregisterMainAppLoginItem: (() throws -> Void)? = nil,
        setActivationPolicy: ((NSApplication.ActivationPolicy) -> Void)? = nil,
        openURL: ((URL) -> Void)? = nil
    ) {
        self.store = store
        self.settings = settings
        self.actions = actions
        self.runningAppProvider = runningAppProvider ?? {
            RunningAppService().fetchRunningApps(includingOffscreenExecutableWindows: true)
        }
        self.windowHelperRegistrationService = windowHelperRegistrationService
            ?? LoginItemWindowHelperRegistrationService()
        self.windowHelperClient = windowHelperClient
            ?? NotificationWindowHelperClient(timeout: 0.25)
        self.windowHelperServiceStatusProvider = windowHelperServiceStatusProvider ?? {
            SMAppService.loginItem(identifier: WindowHelperConfiguration.loginItemIdentifier).status
        }
        self.mainAppLoginItemStatusProvider = mainAppLoginItemStatusProvider ?? { SMAppService.mainApp.status }
        self.registerMainAppLoginItem = registerMainAppLoginItem ?? { try SMAppService.mainApp.register() }
        self.unregisterMainAppLoginItem = unregisterMainAppLoginItem ?? { try SMAppService.mainApp.unregister() }
        self.setActivationPolicy = setActivationPolicy ?? { NSApp.setActivationPolicy($0) }
        self.openURL = openURL ?? { NSWorkspace.shared.open($0) }
        super.init()
        statusMenu.delegate = self
    }

    func setVisible(_ isVisible: Bool) {
        if isVisible {
            installStatusItemIfNeeded()
            refresh()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    func refresh() {
        guard let statusItem else { return }
        configureButton(statusItem.button, showsAccessibilityWarning: store.needsAccessibilityPermission)
        populateMenu(statusMenu)
    }

    /// Uses the passed value because `@Published` sinks fire in `willSet`, before the store holds it.
    func updateAccessibilityWarning(_ isShowing: Bool) {
        configureButton(statusItem?.button, showsAccessibilityWarning: isShowing)
    }

    static func statusSymbolName(showsAccessibilityWarning: Bool) -> String {
        showsAccessibilityWarning ? "exclamationmark.triangle" : "square.grid.2x2"
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = statusMenu
        statusItem = item
    }

    private func configureButton(_ button: NSStatusBarButton?, showsAccessibilityWarning: Bool) {
        let label = showsAccessibilityWarning
            ? L10n.string("statusBar.accessibilityWarning.accessibilityLabel")
            : "GatherApps"
        button?.image = NSImage(
            systemSymbolName: Self.statusSymbolName(showsAccessibilityWarning: showsAccessibilityWarning),
            accessibilityDescription: label
        )
        button?.image?.isTemplate = true
        button?.setAccessibilityLabel(label)
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "GatherApps")
        populateMenu(menu)
        return menu
    }

    private func syncLaunchAtLoginSetting() {
        let status = mainAppLoginItemStatusProvider()
        let isRegistered = status == .enabled || status == .requiresApproval
        if settings.launchesAtLogin != isRegistered {
            settings.launchesAtLogin = isRegistered
        }
    }

    private func populateMenu(_ menu: NSMenu) {
        syncLaunchAtLoginSetting()
        menu.removeAllItems()
        menu.addItem(headerItem(title: "GatherApps"))
        if store.needsAccessibilityPermission {
            menu.addItem(accessibilityWarningItem())
        }
        menu.addItem(.separator())

        let runningAppIdentifiers = Set(runningAppProvider().map(\.id))
        let groupItems = StatusBarMenuModel.groupItems(
            for: store.groups,
            runningAppIdentifiers: runningAppIdentifiers
        )
        if groupItems.isEmpty {
            let emptyItem = NSMenuItem(title: L10n.string("statusBar.noGroups"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            groupItems.forEach { menu.addItem(groupMenuItem($0)) }
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(title: L10n.string("statusBar.openSwitcher"), action: #selector(openSwitcher)))
        menu.addItem(actionItem(
            title: L10n.string("statusBar.openMainWindow"),
            action: #selector(openGatherAppsWindow)
        ))
        menu.addItem(.separator())
        menu.addItem(windowRaisingMenuItem())
        menu.addItem(.separator())
        menu.addItem(toggleItem(
            title: L10n.string("statusBar.launchAtLogin"),
            isOn: settings.launchesAtLogin,
            action: #selector(toggleLaunchAtLogin)
        ))
        menu.addItem(toggleItem(
            title: L10n.string("statusBar.keepInMenuBar"),
            isOn: settings.showsStatusBarItem,
            action: #selector(toggleStatusBarItem)
        ))
        menu.addItem(toggleItem(
            title: L10n.string("statusBar.showDockIcon"),
            isOn: settings.showsDockIcon,
            action: #selector(toggleDockIcon)
        ))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: L10n.string("statusBar.settings"), action: #selector(openGatherAppsWindow)))
        menu.addItem(actionItem(title: L10n.string("statusBar.quit"), action: #selector(quitGatherApps)))
    }

    private func headerItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func accessibilityWarningItem() -> NSMenuItem {
        let item = actionItem(
            title: L10n.string("statusBar.accessibilityWarning.menuItem"),
            action: #selector(requestAccessibilityPermission)
        )
        item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        return item
    }

    private func groupMenuItem(_ group: StatusBarGroupMenuItem) -> NSMenuItem {
        let item = NSMenuItem(title: group.title, action: #selector(activateGroup(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = group.groupID.uuidString
        item.isEnabled = group.isEnabled
        item.toolTip = group.runningCountTitle
        item.attributedTitle = NSAttributedString(
            string: "\(group.title)    \(group.runningCountTitle)"
        )
        return item
    }

    private func actionItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func toggleItem(title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let item = actionItem(title: title, action: action)
        item.state = isOn ? .on : .off
        return item
    }

    private func windowRaisingMenuItem() -> NSMenuItem {
        let submenu = NSMenu(title: L10n.string("statusBar.windowRaising"))
        submenu.delegate = self
        let helperItem = headerItem(title: L10n.string("statusBar.helper.checking"))
        let accessibilityItem = headerItem(title: L10n.string("statusBar.accessibility.checking"))
        submenu.addItem(helperItem)
        submenu.addItem(accessibilityItem)
        windowRaisingMenu = submenu
        windowHelperStatusItem = helperItem
        accessibilityStatusItem = accessibilityItem
        submenu.addItem(actionItem(
            title: L10n.string("statusBar.requestAccessibilityPermission"),
            action: #selector(requestAccessibilityPermission)
        ))
        submenu.addItem(actionItem(
            title: L10n.string("statusBar.openAccessibilitySettings"),
            action: #selector(openAccessibilitySettings)
        ))
        submenu.addItem(actionItem(
            title: L10n.string("statusBar.restartHelper"),
            action: #selector(restartWindowHelper)
        ))

        let item = NSMenuItem(title: L10n.string("statusBar.windowRaising"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func windowHelperStatusTitle(isHelperRunning: Bool) -> String {
        StatusBarWindowHelperStatus.title(
            serviceStatus: windowHelperServiceStatusProvider(),
            isHelperRunning: isHelperRunning
        )
    }

    @objc private func activateGroup(_ sender: NSMenuItem) {
        guard
            let uuidString = sender.representedObject as? String,
            let groupID = UUID(uuidString: uuidString)
        else {
            return
        }

        actions.activateGroup(groupID)
    }

    @objc private func openSwitcher() {
        actions.showSwitcher()
    }

    @objc private func openGatherAppsWindow() {
        actions.showMainWindow()
    }

    @objc func toggleLaunchAtLogin() {
        settings.launchesAtLogin.toggle()
        do {
            if settings.launchesAtLogin {
                try registerMainAppLoginItem()
            } else {
                try unregisterMainAppLoginItem()
            }
            syncLaunchAtLoginSetting()
        } catch {
            settings.launchesAtLogin.toggle()
            store.lastErrorMessage = error.localizedDescription
        }
        refresh()
    }

    @objc func toggleStatusBarItem() {
        if settings.showsStatusBarItem, !settings.showsDockIcon {
            // Hiding the menu bar item with no Dock icon would leave the app without any UI.
            settings.showsDockIcon = true
            setActivationPolicy(.regular)
        }
        settings.showsStatusBarItem.toggle()
    }

    @objc func toggleDockIcon() {
        if settings.showsDockIcon, !settings.showsStatusBarItem { return }
        settings.showsDockIcon.toggle()
        setActivationPolicy(settings.showsDockIcon ? .regular : .accessory)
        refresh()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            openURL(url)
        }
    }

    @objc func requestAccessibilityPermission() {
        Task {
            await performAccessibilityPermissionRequest()
        }
    }

    /// Awaitable body of `requestAccessibilityPermission()`; the helper round-trip suspends instead of blocking.
    func performAccessibilityPermissionRequest() async {
        switch await windowHelperRegistrationService.ensureRegistered() {
        case .available:
            let runtimeInfo = await windowHelperClient.requestAccessibilityPermission()
            if runtimeInfo == nil {
                store.lastErrorMessage = L10n.format(
                    "activation.helperUnavailable",
                    L10n.string("activation.reason.helperDidNotRespond")
                )
            } else if runtimeInfo?.accessibilityTrusted == true {
                store.clearAccessibilityPermissionWarning()
            }
            openAccessibilitySettings()
        case .unavailable(let reason):
            store.lastErrorMessage = L10n.format("activation.helperUnavailable", reason)
        }
        refresh()
    }

    @objc private func restartWindowHelper() {
        Task {
            if case .unavailable(let reason) = await windowHelperRegistrationService.restart() {
                store.lastErrorMessage = L10n.format("activation.helperUnavailable", reason)
            }
            refresh()
        }
    }

    /// Probes the helper and fills in the Window Raising status items, which start out as "Checking...".
    func updateWindowRaisingStatus() async {
        let runtimeInfo = await windowHelperClient.probe()
        windowHelperStatusItem?.title = L10n.format(
            "statusBar.helper.format",
            windowHelperStatusTitle(isHelperRunning: runtimeInfo != nil)
        )
        let accessibilityTitle = StatusBarAccessibilityStatus.title(runtimeInfo: runtimeInfo)
        accessibilityStatusItem?.title = L10n.format("statusBar.accessibility.format", accessibilityTitle)
        if runtimeInfo?.accessibilityTrusted == true {
            store.clearAccessibilityPermissionWarning()
        }
    }

    @objc private func quitGatherApps() {
        NSApp.terminate(nil)
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusMenu {
            populateMenu(menu)
            return
        }
        guard menu === windowRaisingMenu else { return }

        // Keep the "Checking..." titles from populateMenu until the probe answers.
        Task {
            await updateWindowRaisingStatus()
        }
    }
}
