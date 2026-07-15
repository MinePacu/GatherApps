import Foundation
import XCTest
@testable import GatherApps

@MainActor
final class WindowHelperIPCTests: XCTestCase {
    func testProbeReturnsRuntimeInformationFromExpectedHelper() {
        let expectedURL = Bundle.main.bundleURL
        let center = DistributedNotificationCenter.default()
        let observer = installResponder(center: center) { request in
            XCTAssertEqual(
                request[WindowHelperNotification.operationKey] as? String,
                WindowHelperOperation.probe.rawValue
            )
            return self.response(
                for: request,
                helperURL: expectedURL,
                accessibilityTrusted: true
            )
        }
        defer { center.removeObserver(observer) }

        let client = NotificationWindowHelperClient(timeout: 0.5, expectedHelperURL: expectedURL)

        XCTAssertEqual(
            client.probe(),
            WindowHelperRuntimeInfo(
                bundleURL: expectedURL,
                protocolVersion: WindowHelperConfiguration.protocolVersion,
                accessibilityTrusted: true
            )
        )
    }

    func testClientIgnoresResponseFromUnexpectedHelperPath() {
        let expectedURL = Bundle.main.bundleURL
        let unexpectedURL = expectedURL
            .deletingLastPathComponent()
            .appendingPathComponent("StaleHelper.app", isDirectory: true)
        let center = DistributedNotificationCenter.default()
        let observer = installResponder(center: center) { request in
            self.response(
                for: request,
                helperURL: unexpectedURL,
                accessibilityTrusted: true
            )
        }
        defer { center.removeObserver(observer) }

        let client = NotificationWindowHelperClient(timeout: 0.05, expectedHelperURL: expectedURL)

        XCTAssertNil(client.probe())
    }

    func testPermissionRequestUsesDedicatedOperation() {
        let expectedURL = Bundle.main.bundleURL
        let center = DistributedNotificationCenter.default()
        var receivedOperation: String?
        let observer = installResponder(center: center) { request in
            receivedOperation = request[WindowHelperNotification.operationKey] as? String
            return self.response(
                for: request,
                helperURL: expectedURL,
                accessibilityTrusted: false
            )
        }
        defer { center.removeObserver(observer) }

        let client = NotificationWindowHelperClient(timeout: 0.5, expectedHelperURL: expectedURL)
        let runtimeInfo = client.requestAccessibilityPermission()

        XCTAssertEqual(receivedOperation, WindowHelperOperation.requestAccessibilityPermission.rawValue)
        XCTAssertEqual(runtimeInfo?.accessibilityTrusted, false)
    }

    func testProcessResultDecodesWindowActivationResponse() {
        let result = WindowHelperProcessResult(userInfo: [
            WindowHelperNotification.bundleIdentifierKey: "com.example.App",
            WindowHelperNotification.appNameKey: "Example",
            WindowHelperNotification.statusKey: "raised",
            WindowHelperNotification.raisedWindowCountKey: 2,
            WindowHelperNotification.helperBundlePathKey: Bundle.main.bundleURL.path,
            WindowHelperNotification.protocolVersionKey: WindowHelperConfiguration.protocolVersion,
            WindowHelperNotification.accessibilityTrustedKey: true
        ])

        XCTAssertEqual(result.activationResult, .raised(appName: "Example", raisedWindowCount: 2))
        XCTAssertEqual(result.runtimeInfo?.accessibilityTrusted, true)
    }

    func testHelperPromptsOnlyForDedicatedPermissionRequest() throws {
        let projectRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let helperSourceURL = projectRootURL
            .appendingPathComponent("GatherAppsWindowHelper", isDirectory: true)
            .appendingPathComponent("main.swift")
        let source = try String(contentsOf: helperSourceURL, encoding: .utf8)

        XCTAssertEqual(source.components(separatedBy: "AXIsProcessTrustedWithOptions").count - 1, 1)
        XCTAssertTrue(source.contains("guard AXIsProcessTrusted() else"))
        XCTAssertTrue(source.contains("case .requestAccessibilityPermission:"))
    }

    private func installResponder(
        center: DistributedNotificationCenter,
        responseProvider: @escaping ([AnyHashable: Any]) -> [String: Any]
    ) -> NSObjectProtocol {
        center.addObserver(
            forName: WindowHelperNotification.request,
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo else { return }
            center.postNotificationName(
                WindowHelperNotification.response,
                object: nil,
                userInfo: responseProvider(userInfo),
                deliverImmediately: true
            )
        }
    }

    private func response(
        for request: [AnyHashable: Any],
        helperURL: URL,
        accessibilityTrusted: Bool
    ) -> [String: Any] {
        [
            WindowHelperNotification.requestIDKey: request[WindowHelperNotification.requestIDKey] as? String ?? "",
            WindowHelperNotification.statusKey: "ready",
            WindowHelperNotification.helperBundlePathKey: helperURL.path,
            WindowHelperNotification.protocolVersionKey: WindowHelperConfiguration.protocolVersion,
            WindowHelperNotification.accessibilityTrustedKey: accessibilityTrusted
        ]
    }
}
