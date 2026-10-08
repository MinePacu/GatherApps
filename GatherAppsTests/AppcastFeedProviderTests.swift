import XCTest
@testable import GatherApps

@MainActor
final class AppcastFeedProviderTests: XCTestCase {
    func testAppcastFeedProviderUsesGitLabBeforeGitHubFallback() {
        var provider = AppcastFeedProvider()

        XCTAssertEqual(
            provider.currentFeedURL?.absoluteString,
            "https://gitlab.com/MinePacu/GatherApps/-/releases/permalink/latest/downloads/appcast.xml"
        )

        XCTAssertTrue(provider.advanceToFallbackFeed())
        XCTAssertEqual(
            provider.currentFeedURL?.absoluteString,
            "https://github.com/MinePacu/GatherApps/releases/latest/download/appcast.xml"
        )
        XCTAssertFalse(provider.advanceToFallbackFeed())
    }

    func testAppcastFeedProviderResetReturnsToGitLabFeed() {
        var provider = AppcastFeedProvider()

        XCTAssertTrue(provider.advanceToFallbackFeed())
        provider.resetToPrimaryFeed()

        XCTAssertEqual(
            provider.currentFeedURL?.absoluteString,
            "https://gitlab.com/MinePacu/GatherApps/-/releases/permalink/latest/downloads/appcast.xml"
        )
        XCTAssertTrue(provider.advanceToFallbackFeed())
    }

    func testAppcastFeedProviderFallsBackOnlyForFeedErrors() {
        let sparkleErrorDomain = "SUSparkleErrorDomain"

        XCTAssertFalse(AppcastFeedProvider.shouldTryFallbackFeed(after: nil))
        XCTAssertFalse(
            AppcastFeedProvider.shouldTryFallbackFeed(after: NSError(domain: sparkleErrorDomain, code: 1001))
        )
        XCTAssertFalse(
            AppcastFeedProvider.shouldTryFallbackFeed(after: NSError(domain: sparkleErrorDomain, code: 4007))
        )
        XCTAssertFalse(
            AppcastFeedProvider.shouldTryFallbackFeed(after: NSError(domain: NSURLErrorDomain, code: 1000))
        )

        XCTAssertTrue(
            AppcastFeedProvider.shouldTryFallbackFeed(after: NSError(domain: sparkleErrorDomain, code: 1000))
        )
        XCTAssertTrue(
            AppcastFeedProvider.shouldTryFallbackFeed(after: NSError(domain: sparkleErrorDomain, code: 1002))
        )
        XCTAssertTrue(
            AppcastFeedProvider.shouldTryFallbackFeed(after: NSError(domain: sparkleErrorDomain, code: 2001))
        )
    }
}
