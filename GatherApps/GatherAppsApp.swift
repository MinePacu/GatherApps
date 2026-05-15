import SwiftUI

@main
struct GatherAppsApp: App {
    @StateObject private var updateService = SparkleUpdateService()

    var body: some Scene {
        Window("GatherApps", id: "main") {
            ContentView()
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
