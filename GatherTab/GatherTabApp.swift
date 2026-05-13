import SwiftUI

@main
struct GatherTabApp: App {
    var body: some Scene {
        Window("GatherTab", id: "main") {
            ContentView()
        }
        .defaultSize(width: AppLayout.defaultWindowWidth, height: AppLayout.defaultWindowHeight)
        .windowResizability(.contentMinSize)
    }
}
