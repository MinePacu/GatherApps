import Foundation
import XCTest
@testable import GatherApps

final class StatusBarWindowHelperTests: XCTestCase {
    func testAccessibilityStatusUsesHelperRuntimeInformation() {
        let helperURL = URL(
            fileURLWithPath: "/Applications/GatherApps.app/Contents/Library/LoginItems/Helper.app"
        )

        XCTAssertEqual(StatusBarAccessibilityStatus.title(runtimeInfo: nil), "Unavailable")
        XCTAssertEqual(
            StatusBarAccessibilityStatus.title(runtimeInfo: WindowHelperRuntimeInfo(
                bundleURL: helperURL,
                protocolVersion: WindowHelperConfiguration.protocolVersion,
                accessibilityTrusted: false
            )),
            "Needs Permission"
        )
        XCTAssertEqual(
            StatusBarAccessibilityStatus.title(runtimeInfo: WindowHelperRuntimeInfo(
                bundleURL: helperURL,
                protocolVersion: WindowHelperConfiguration.protocolVersion,
                accessibilityTrusted: true
            )),
            "Granted"
        )
    }
}
