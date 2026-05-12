import SwiftUI

@main
struct GatherTabApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: AppLayout.defaultWindowWidth, height: AppLayout.defaultWindowHeight)
        .windowResizability(.contentMinSize)
    }
}
