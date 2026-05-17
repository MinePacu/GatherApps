import Foundation
import Combine
import Sparkle

struct AppcastFeedProvider {
    static let gitLabFeedURL = URL(
        string: "https://gitlab.com/MinePacu/GatherApps/-/releases/permalink/latest/downloads/appcast.xml"
    )!
    static let gitHubFeedURL = URL(
        string: "https://github.com/MinePacu/GatherApps/releases/latest/download/appcast.xml"
    )!

    private let feedURLs: [URL]
    private var currentIndex = 0

    var currentFeedURL: URL? {
        guard feedURLs.indices.contains(currentIndex) else {
            return nil
        }

        return feedURLs[currentIndex]
    }

    init(feedURLs: [URL] = [Self.gitLabFeedURL, Self.gitHubFeedURL]) {
        self.feedURLs = feedURLs
    }

    mutating func advanceToFallbackFeed() -> Bool {
        guard currentIndex + 1 < feedURLs.count else {
            return false
        }

        currentIndex += 1
        return true
    }
}

@MainActor
protocol UpdateChecking: ObservableObject {
    var canCheckForUpdates: Bool { get }
    func checkForUpdates()
}

@MainActor
final class SparkleUpdateService: NSObject, UpdateChecking, ObservableObject {
    private let updaterDelegate: SparkleAppcastFeedDelegate
    private let updaterController: SPUStandardUpdaterController

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    override init() {
        updaterDelegate = SparkleAppcastFeedDelegate()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
        super.init()
        updaterDelegate.updaterController = updaterController
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

@MainActor
private final class SparkleAppcastFeedDelegate: NSObject, SPUUpdaterDelegate {
    weak var updaterController: SPUStandardUpdaterController?
    private var appcastFeedProvider: AppcastFeedProvider

    override init() {
        appcastFeedProvider = AppcastFeedProvider()
        super.init()
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        appcastFeedProvider.currentFeedURL?.absoluteString
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        guard appcastFeedProvider.advanceToFallbackFeed() else {
            return
        }

        Task { @MainActor in
            updaterController?.checkForUpdates(nil)
        }
    }
}
