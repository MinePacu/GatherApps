import Foundation
import Combine
import Sparkle

@MainActor
protocol UpdateChecking: ObservableObject {
    var canCheckForUpdates: Bool { get }
    func checkForUpdates()
}

@MainActor
final class SparkleUpdateService: NSObject, UpdateChecking, ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
