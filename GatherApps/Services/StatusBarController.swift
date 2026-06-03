import AppKit
import ApplicationServices
import ServiceManagement

struct StatusBarActions {
    let activateGroup: (AppGroup.ID) -> Void
    let showSwitcher: () -> Void
    let showMainWindow: () -> Void
}

@MainActor
final class StatusBarController: NSObject {
    private let store: AppGroupStore
    private let settings: MenuBarSettings
    private let actions: StatusBarActions
    private let runningAppProvider: () -> [RunningAppInfo]
    private var statusItem: NSStatusItem?

    init(
        store: AppGroupStore,
        settings: MenuBarSettings,
        actions: StatusBarActions,
        runningAppProvider: (() -> [RunningAppInfo])? = nil
    ) {
        self.store = store
        self.settings = settings
        self.actions = actions
        self.runningAppProvider = runningAppProvider ?? {
            RunningAppService().fetchRunningApps()
        }
        super.init()
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
        configureButton(statusItem.button)
        statusItem.menu = makeMenu()
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }

    private func configureButton(_ button: NSStatusBarButton?) {
        button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "GatherApps")
        button?.image?.isTemplate = true
        button?.setAccessibilityLabel("GatherApps")
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "GatherApps")
        menu.addItem(headerItem(title: "GatherApps"))
        menu.addItem(.separator())

        let runningAppIdentifiers = Set(runningAppProvider().map(\.id))
        let groupItems = StatusBarMenuModel.groupItems(
            for: store.groups,
            runningAppIdentifiers: runningAppIdentifiers
        )
        if groupItems.isEmpty {
            let emptyItem = NSMenuItem(title: "No Groups", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            groupItems.forEach { menu.addItem(groupMenuItem($0)) }
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Open Switcher", action: #selector(openSwitcher)))
        menu.addItem(actionItem(title: "Open GatherApps Window", action: #selector(openGatherAppsWindow)))
        menu.addItem(.separator())
        menu.addItem(windowRaisingMenuItem())
        menu.addItem(.separator())
        menu.addItem(toggleItem(
            title: "Launch at Login",
            isOn: settings.launchesAtLogin,
            action: #selector(toggleLaunchAtLogin)
        ))
        menu.addItem(toggleItem(
            title: "Keep GatherApps in Menu Bar",
            isOn: settings.showsStatusBarItem,
            action: #selector(toggleStatusBarItem)
        ))
        menu.addItem(toggleItem(
            title: "Show Dock Icon",
            isOn: settings.showsDockIcon,
            action: #selector(toggleDockIcon)
        ))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Settings...", action: #selector(openGatherAppsWindow)))
        menu.addItem(actionItem(title: "Quit GatherApps", action: #selector(quitGatherApps)))

        return menu
    }

    private func headerItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
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
        let submenu = NSMenu(title: "Window Raising")
        submenu.addItem(headerItem(title: "Helper: \(windowHelperStatusTitle())"))
        submenu.addItem(headerItem(title: "Accessibility: \(accessibilityStatusTitle())"))
        submenu.addItem(actionItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings)))
        submenu.addItem(actionItem(title: "Restart Window Helper", action: #selector(restartWindowHelper)))

        let item = NSMenuItem(title: "Window Raising", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func windowHelperStatusTitle() -> String {
        switch SMAppService.loginItem(identifier: WindowHelperConfiguration.loginItemIdentifier).status {
        case .enabled:
            return "Running"
        case .requiresApproval:
            return "Needs Approval"
        default:
            return "Unavailable"
        }
    }

    private func accessibilityStatusTitle() -> String {
        AXIsProcessTrusted() ? "Granted" : "Needs Permission"
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

    @objc private func toggleLaunchAtLogin() {
        settings.launchesAtLogin.toggle()
        do {
            if settings.launchesAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            settings.launchesAtLogin.toggle()
            store.lastErrorMessage = error.localizedDescription
        }
        refresh()
    }

    @objc private func toggleStatusBarItem() {
        settings.showsStatusBarItem.toggle()
    }

    @objc private func toggleDockIcon() {
        settings.showsDockIcon.toggle()
        NSApp.setActivationPolicy(settings.showsDockIcon ? .regular : .accessory)
        refresh()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func restartWindowHelper() {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == WindowHelperConfiguration.loginItemIdentifier }
            .forEach { $0.terminate() }

        let deadline = Date().addingTimeInterval(2)
        while NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == WindowHelperConfiguration.loginItemIdentifier
        }), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        _ = LoginItemWindowHelperRegistrationService().ensureRegistered()
        refresh()
    }

    @objc private func quitGatherApps() {
        NSApp.terminate(nil)
    }
}
