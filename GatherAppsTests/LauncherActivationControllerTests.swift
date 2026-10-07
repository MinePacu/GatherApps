import XCTest
@testable import GatherApps

final class LauncherActivationControllerTests: XCTestCase {
    func testHandlingActivationDispatchesGroupAndHidesLauncher() {
        var dispatchCount = 0
        var hideCount = 0
        let controller = LauncherActivationController(
            dispatchActivation: { dispatchCount += 1 },
            hideLauncher: { hideCount += 1 }
        )

        controller.handleActivation()

        XCTAssertEqual(dispatchCount, 1)
        XCTAssertEqual(hideCount, 1)
    }

    func testDuplicateActivationStillHidesLauncherWithoutRedispatchingGroup() {
        let activationDate = Date()
        var dispatchCount = 0
        var hideCount = 0
        let controller = LauncherActivationController(
            now: { activationDate },
            dispatchActivation: { dispatchCount += 1 },
            hideLauncher: { hideCount += 1 }
        )

        controller.handleActivation()
        controller.handleActivation()

        XCTAssertEqual(dispatchCount, 1)
        XCTAssertEqual(hideCount, 2)
    }
}
