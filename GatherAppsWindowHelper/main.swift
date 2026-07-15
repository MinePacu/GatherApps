import AppKit
import ApplicationServices
import Foundation

struct HelperResult {
    let bundleIdentifier: String
    let appName: String?
    let status: String
    let raisedWindowCount: Int?
    let message: String?
    let accessibilityTrusted: Bool
}

private enum WindowHelperConfiguration {
    static let notificationNamespace = "com.minepacu.GatherApps.WindowHelper"
    static let protocolVersion = 1
}

private enum WindowHelperOperation: String {
    case raiseWindows
    case probe
    case requestAccessibilityPermission
}

private enum WindowHelperNotification {
    static let request = Notification.Name("\(WindowHelperConfiguration.notificationNamespace).request")
    static let response = Notification.Name("\(WindowHelperConfiguration.notificationNamespace).response")
    static let bundleIdentifierKey = "bundleIdentifier"
    static let requestIDKey = "requestID"
    static let operationKey = "operation"
    static let appNameKey = "appName"
    static let statusKey = "status"
    static let raisedWindowCountKey = "raisedWindowCount"
    static let messageKey = "message"
    static let helperBundlePathKey = "helperBundlePath"
    static let protocolVersionKey = "protocolVersion"
    static let accessibilityTrustedKey = "accessibilityTrusted"
}

private final class HelperAppDelegate: NSObject, NSApplicationDelegate {
    private let server = NotificationWindowHelperServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        server.start()
    }
}

private final class NotificationWindowHelperServer {
    private let center = DistributedNotificationCenter.default()
    private var observer: NSObjectProtocol?

    func start() {
        observer = center.addObserver(
            forName: WindowHelperNotification.request,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handle(notification)
        }
    }

    private func handle(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let requestID = userInfo[WindowHelperNotification.requestIDKey] as? String,
            userInfo[WindowHelperNotification.protocolVersionKey] as? Int == WindowHelperConfiguration.protocolVersion,
            let operationValue = userInfo[WindowHelperNotification.operationKey] as? String,
            let operation = WindowHelperOperation(rawValue: operationValue)
        else {
            return
        }

        let result: HelperResult
        switch operation {
        case .raiseWindows:
            guard let bundleIdentifier = userInfo[WindowHelperNotification.bundleIdentifierKey] as? String else {
                return
            }
            result = WindowRaiser.raiseWindows(bundleIdentifier: bundleIdentifier)
        case .probe:
            result = WindowRaiser.runtimeResult(status: "ready")
        case .requestAccessibilityPermission:
            result = WindowRaiser.requestAccessibilityPermission()
        }

        center.postNotificationName(
            WindowHelperNotification.response,
            object: nil,
            userInfo: result.userInfo(requestID: requestID),
            deliverImmediately: true
        )
    }
}

private struct WindowRaiser {
    static func raiseWindows(bundleIdentifier: String) -> HelperResult {
        guard AXIsProcessTrusted() else {
            return accessibilityPermissionMissingResult(bundleIdentifier: bundleIdentifier)
        }

        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            return appNotRunningResult(bundleIdentifier: bundleIdentifier)
        }

        let appName = app.localizedName ?? bundleIdentifier
        _ = app.activate(options: [.activateAllWindows])

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?
        let copyResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )

        guard copyResult == .success else {
            return windowReadFailedResult(
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                copyResult: copyResult
            )
        }

        guard let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
            return noWindowsFoundResult(bundleIdentifier: bundleIdentifier, appName: appName)
        }

        let raisedWindowCount = windows.reduce(0) { count, window in
            AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success ? count + 1 : count
        }

        return HelperResult(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            status: raisedWindowCount > 0 ? "raised" : "raiseFailed",
            raisedWindowCount: raisedWindowCount,
            message: raisedWindowCount > 0 ? nil : "No windows accepted AXRaise.",
            accessibilityTrusted: true
        )
    }

    static func runtimeResult(status: String) -> HelperResult {
        HelperResult(
            bundleIdentifier: "",
            appName: nil,
            status: status,
            raisedWindowCount: nil,
            message: nil,
            accessibilityTrusted: AXIsProcessTrusted()
        )
    }

    static func requestAccessibilityPermission() -> HelperResult {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)

        return HelperResult(
            bundleIdentifier: "",
            appName: nil,
            status: isTrusted ? "accessibilityGranted" : "accessibilityPermissionMissing",
            raisedWindowCount: nil,
            message: nil,
            accessibilityTrusted: isTrusted
        )
    }

    private static func accessibilityPermissionMissingResult(bundleIdentifier: String) -> HelperResult {
        HelperResult(
            bundleIdentifier: bundleIdentifier,
            appName: nil,
            status: "accessibilityPermissionMissing",
            raisedWindowCount: nil,
            message: "Accessibility permission is required for GatherAppsWindowHelper.",
            accessibilityTrusted: false
        )
    }

    private static func appNotRunningResult(bundleIdentifier: String) -> HelperResult {
        HelperResult(
            bundleIdentifier: bundleIdentifier,
            appName: nil,
            status: "appNotRunning",
            raisedWindowCount: nil,
            message: nil,
            accessibilityTrusted: true
        )
    }

    private static func windowReadFailedResult(
        bundleIdentifier: String,
        appName: String,
        copyResult: AXError
    ) -> HelperResult {
        HelperResult(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            status: "raiseFailed",
            raisedWindowCount: nil,
            message: "Unable to read AXWindows: \(copyResult.rawValue)",
            accessibilityTrusted: true
        )
    }

    private static func noWindowsFoundResult(bundleIdentifier: String, appName: String) -> HelperResult {
        HelperResult(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            status: "noWindowsFound",
            raisedWindowCount: 0,
            message: nil,
            accessibilityTrusted: true
        )
    }
}

private extension HelperResult {
    func userInfo(requestID: String) -> [String: Any] {
        var result: [String: Any] = [
            WindowHelperNotification.requestIDKey: requestID,
            WindowHelperNotification.bundleIdentifierKey: bundleIdentifier,
            WindowHelperNotification.statusKey: status,
            WindowHelperNotification.helperBundlePathKey: Bundle.main.bundleURL.path,
            WindowHelperNotification.protocolVersionKey: WindowHelperConfiguration.protocolVersion,
            WindowHelperNotification.accessibilityTrustedKey: accessibilityTrusted
        ]

        if let appName {
            result[WindowHelperNotification.appNameKey] = appName
        }
        if let raisedWindowCount {
            result[WindowHelperNotification.raisedWindowCountKey] = raisedWindowCount
        }
        if let message {
            result[WindowHelperNotification.messageKey] = message
        }

        return result
    }
}

let app = NSApplication.shared
private let delegate = HelperAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.prohibited)
app.run()
