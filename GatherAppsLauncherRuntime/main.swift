import AppKit

private final class LauncherAppDelegate: NSObject, NSApplicationDelegate {
    private var lastActivationDate = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        activateGroup()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        activateGroup()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        activateGroup()
        return true
    }

    private func activateGroup() {
        guard Date().timeIntervalSince(lastActivationDate) > 0.5 else { return }
        lastActivationDate = Date()

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
