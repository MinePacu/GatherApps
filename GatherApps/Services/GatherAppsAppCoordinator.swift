import AppKit
import Combine
import Foundation

@MainActor
final class GatherAppsAppCoordinator: ObservableObject {
    let store: AppGroupStore
    let settings: MenuBarSettings
    var showMainWindowAction: (() -> Void)?

    private let showSwitcherAction: (AppGroupStore) -> Void
    private let activateAppAction: () -> Void
    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Void
    private let switcherWindowController: SwitcherWindowController
    private var statusBarController: StatusBarController?
    private var cancellables: Set<AnyCancellable> = []

    init(
        store: AppGroupStore? = nil,
        settings: MenuBarSettings? = nil,
        switcherWindowController: SwitcherWindowController? = nil,
        showSwitcherAction: ((AppGroupStore) -> Void)? = nil,
        activateAppAction: (() -> Void)? = nil,
        setActivationPolicy: ((NSApplication.ActivationPolicy) -> Void)? = nil
    ) {
        let store = store ?? AppGroupStore()
        let settings = settings ?? MenuBarSettings()
        let switcherWindowController = switcherWindowController ?? SwitcherWindowController()

        self.store = store
        self.settings = settings
        self.switcherWindowController = switcherWindowController
        self.showSwitcherAction = showSwitcherAction ?? { store in
            switcherWindowController.showSwitcher(store: store)
        }
        self.activateAppAction = activateAppAction ?? {
            NSApp.activate(ignoringOtherApps: true)
        }
        self.setActivationPolicy = setActivationPolicy ?? { NSApp.setActivationPolicy($0) }

        store.$groups
            .sink { [weak self] _ in
                self?.statusBarController?.refresh()
            }
            .store(in: &cancellables)

        store.$needsAccessibilityPermission
            .removeDuplicates()
            .sink { [weak self] isShowing in
                self?.statusBarController?.updateAccessibilityWarning(isShowing)
            }
            .store(in: &cancellables)

        settings.$showsStatusBarItem
            .sink { [weak self] isVisible in
                self?.statusBarController?.setVisible(isVisible)
            }
            .store(in: &cancellables)
    }

    func startStatusBar() {
        guard statusBarController == nil else { return }
        if !settings.showsDockIcon, !settings.showsStatusBarItem {
            // Older builds allowed hiding both; keep at least one way to reach the app.
            settings.showsDockIcon = true
        }
        setActivationPolicy(settings.showsDockIcon ? .regular : .accessory)
        statusBarController = StatusBarController(
            store: store,
            settings: settings,
            actions: StatusBarActions(
                activateGroup: { [weak self] groupID in
                    self?.activateGroup(id: groupID)
                },
                showSwitcher: { [weak self] in
                    self?.showSwitcher()
                },
                showMainWindow: { [weak self] in
                    self?.showMainWindow()
                }
            ),
            setActivationPolicy: setActivationPolicy
        )
        statusBarController?.setVisible(settings.showsStatusBarItem)
    }

    /// Activation suspends while it waits on macOS and the window helper, so it runs in a main-actor task.
    @discardableResult
    func activateGroup(id groupID: AppGroup.ID) -> Task<Void, Never> {
        Task {
            await store.activate(groupID: groupID)
            statusBarController?.refresh()
        }
    }

    func showSwitcher() {
        showSwitcherAction(store)
    }

    func showMainWindow() {
        activateAppAction()
        showMainWindowAction?()
    }

    func handleActivationURL(_ url: URL) {
        Task {
            guard let groupID = await store.handleActivationURL(url) else { return }
            statusBarController?.refresh()

            if GatherAppsURLScheme.showsGatherAppsWindow(from: url) {
                showMainWindow()
            } else {
                NSApp.hide(nil)
            }

            _ = groupID
        }
    }
}
