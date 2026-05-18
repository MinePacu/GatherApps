import SwiftUI

@main
struct GatherAppsApp: App {
    @StateObject private var updateService = SparkleUpdateService()
    @StateObject private var coordinator = GatherAppsAppCoordinator()
    @NSApplicationDelegateAdaptor(GatherAppsApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        Window("GatherApps", id: "main") {
            GatherAppsRootView(coordinator: coordinator)
                .onAppear {
                    coordinator.startStatusBar()
                }
        }
        .defaultSize(width: AppLayout.defaultWindowWidth, height: AppLayout.defaultWindowHeight)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("updates.checkForUpdates") {
                    updateService.checkForUpdates()
                }
                .disabled(!updateService.canCheckForUpdates)
            }
        }
    }
}

private struct GatherAppsRootView: View {
    @ObservedObject var coordinator: GatherAppsAppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView(
            store: coordinator.store,
            showSwitcher: coordinator.showSwitcher,
            handleActivationURL: coordinator.handleActivationURL
        )
        .onAppear {
            coordinator.showMainWindowAction = {
                openWindow(id: "main")
            }
        }
    }
}

final class GatherAppsApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
