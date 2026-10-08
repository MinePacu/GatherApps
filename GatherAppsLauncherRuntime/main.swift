import AppKit

private final class LauncherAppDelegate: NSObject, NSApplicationDelegate {
    private lazy var activationController = LauncherActivationController(
        dispatchActivation: Self.dispatchActivation,
        hideLauncher: {
            // A generated launcher has no windows. Keeping it unhidden lets macOS
            // make it active after an unrelated window closes, which would
            // reactivate the group from applicationDidBecomeActive.
            NSApp.hide(nil)
        }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        activationController.handleLaunch(arguments: CommandLine.arguments)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        activationController.handleActivation()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        activationController.handleActivation()
        return true
    }

    private static func dispatchActivation() {
        guard
            let groupID = Bundle.main.object(forInfoDictionaryKey: "GatherAppsGroupID") as? String,
            var components = URLComponents(string: "gatherapps://activate-group/\(groupID)")
        else {
            return
        }

        let showsGatherAppsWindow = Bundle.main
            .object(forInfoDictionaryKey: "GatherAppsShowsGatherAppsWindow") as? Bool ?? true
        if !showsGatherAppsWindow {
            components.queryItems = [
                URLQueryItem(name: "showWindow", value: "false")
            ]
        }

        guard let url = components.url else { return }

        if
            let appPath = Bundle.main.object(forInfoDictionaryKey: "GatherAppsApplicationPath") as? String,
            FileManager.default.fileExists(atPath: appPath) {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: URL(fileURLWithPath: appPath),
                configuration: configuration
            )
            return
        }

        NSWorkspace.shared.open(url)
    }
}

let app = NSApplication.shared
private let delegate = LauncherAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
