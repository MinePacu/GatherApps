import XCTest
@testable import GatherApps

@MainActor
final class ContentViewTests: XCTestCase {
    func testToolbarDeletionCapturesTargetAndDeletesOnlyOnConfirmation() {
        let requestedGroup = AppGroup(name: "Writing")
        var currentlySelectedGroup = requestedGroup
        var confirmation = ToolbarDeletionConfirmationState()
        var deletedGroupIDs: [AppGroup.ID] = []

        confirmation.request(for: currentlySelectedGroup)

        XCTAssertTrue(deletedGroupIDs.isEmpty)
        XCTAssertEqual(confirmation.pendingRequest?.groupID, requestedGroup.id)
        XCTAssertEqual(confirmation.pendingRequest?.groupName, requestedGroup.name)

        currentlySelectedGroup = AppGroup(name: "Development")
        XCTAssertNotEqual(currentlySelectedGroup.id, confirmation.pendingRequest?.groupID)
        confirmation.confirm { deletedGroupIDs.append($0) }

        XCTAssertEqual(deletedGroupIDs, [requestedGroup.id])
        XCTAssertNil(confirmation.pendingRequest)
    }

    func testToolbarDeletionCancellationDoesNotDeleteOrKeepPendingRequest() {
        let group = AppGroup(name: "Writing")
        var confirmation = ToolbarDeletionConfirmationState()
        var deletedGroupIDs: [AppGroup.ID] = []

        confirmation.request(for: group)
        confirmation.cancel()
        confirmation.confirm { deletedGroupIDs.append($0) }

        XCTAssertTrue(deletedGroupIDs.isEmpty)
        XCTAssertNil(confirmation.pendingRequest)
    }
}
