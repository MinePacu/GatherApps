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

    func testBackgroundRelaunchHidesLauncherWithoutDispatchingGroup() {
        var currentDate = Date()
        var dispatchCount = 0
        var hideCount = 0
        let controller = LauncherActivationController(
            now: { currentDate },
            dispatchActivation: { dispatchCount += 1 },
            hideLauncher: { hideCount += 1 }
        )

        controller.handleLaunch(arguments: ["x", LauncherActivationController.backgroundRelaunchArgument])

        XCTAssertEqual(dispatchCount, 0)
        XCTAssertEqual(hideCount, 1)

        controller.handleActivation()

        XCTAssertEqual(dispatchCount, 0)
        XCTAssertEqual(hideCount, 2)

        currentDate = currentDate.addingTimeInterval(1)
        controller.handleActivation()

        XCTAssertEqual(dispatchCount, 1)
        XCTAssertEqual(hideCount, 3)
    }

    func testRegularLaunchDispatchesGroupAndHidesLauncher() {
        let launchDate = Date()
        var dispatchCount = 0
        var hideCount = 0
        let controller = LauncherActivationController(
            now: { launchDate },
            dispatchActivation: { dispatchCount += 1 },
            hideLauncher: { hideCount += 1 }
        )

        controller.handleLaunch(arguments: ["x"])

        XCTAssertEqual(dispatchCount, 1)
        XCTAssertEqual(hideCount, 1)
    }
}
