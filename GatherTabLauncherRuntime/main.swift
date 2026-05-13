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
            let groupID = Bundle.main.object(forInfoDictionaryKey: "GatherTabGroupID") as? String,
            var components = URLComponents(string: "gathertab://activate-group/\(groupID)")
        else {
            return
        }

        let showsGatherTabWindow = Bundle.main.object(forInfoDictionaryKey: "GatherTabShowsGatherTabWindow") as? Bool ?? true
        if !showsGatherTabWindow {
            components.queryItems = [
                URLQueryItem(name: "showWindow", value: "false")
            ]
        }

        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}

let app = NSApplication.shared
private let delegate = LauncherAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
