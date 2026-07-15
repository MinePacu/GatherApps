import AppKit
import Foundation

protocol ActivatableApplication {
    var bundleIdentifier: String? { get }
    var localizedName: String? { get }
    var processIdentifier: pid_t { get }

    func activate(options: NSApplication.ActivationOptions) -> Bool
}

protocol ApplicationProviding {
    func runningApplication(bundleIdentifier: String) -> ActivatableApplication?
    func runningApplication(executablePath: String) -> ActivatableApplication?
}

protocol AppActivationProviding {
    func activate(_ app: GroupedApp) -> ActivationResult
    func activate(bundleIdentifier: String) -> ActivationResult
}

enum WindowHelperActivationResult: Equatable {
    case raised(appName: String, raisedWindowCount: Int)
    case appNotRunning(bundleIdentifier: String)
    case accessibilityPermissionMissing
    case noWindowsFound(appName: String)
    case raiseFailed(appName: String)
    case helperUnavailable(reason: String)
}

enum WindowHelperRegistrationResult: Equatable {
    case available
    case unavailable(reason: String)
}

protocol WindowHelperRegistrationProviding {
    func ensureRegistered() -> WindowHelperRegistrationResult
    func restart() -> WindowHelperRegistrationResult
}

extension WindowHelperRegistrationProviding {
    func restart() -> WindowHelperRegistrationResult {
        ensureRegistered()
    }
}

protocol WindowHelperClient {
    func raiseWindows(bundleIdentifier: String) -> WindowHelperActivationResult
    func probe() -> WindowHelperRuntimeInfo?
    func requestAccessibilityPermission() -> WindowHelperRuntimeInfo?
}

extension WindowHelperClient {
    func probe() -> WindowHelperRuntimeInfo? { nil }
    func requestAccessibilityPermission() -> WindowHelperRuntimeInfo? { nil }
}

enum WindowHelperConfiguration {
    static let loginItemIdentifier = "com.minepacu.GatherApps.WindowHelper"
    static let notificationNamespace = loginItemIdentifier
    static let protocolVersion = 1
}

struct WindowHelperRuntimeInfo: Equatable {
    let bundleURL: URL
    let protocolVersion: Int
    let accessibilityTrusted: Bool
}

struct AppActivationService: AppActivationProviding {
    private let applicationProvider: ApplicationProviding
    private let helperRegistrationService: WindowHelperRegistrationProviding
    private let helperClient: WindowHelperClient

    init(
        applicationProvider: ApplicationProviding = NSWorkspaceApplicationProvider(),
        helperRegistrationService: WindowHelperRegistrationProviding = LoginItemWindowHelperRegistrationService(),
        helperClient: WindowHelperClient = NotificationWindowHelperClient()
    ) {
        self.applicationProvider = applicationProvider
        self.helperRegistrationService = helperRegistrationService
        self.helperClient = helperClient
    }

    func activate(_ app: GroupedApp) -> ActivationResult {
        switch app.kind {
        case .bundle:
            return activate(bundleIdentifier: app.bundleIdentifier)
        case .executable:
            guard let executablePath = app.executablePath else {
                return .appNotRunning(bundleIdentifier: app.bundleIdentifier)
            }
            return activateExecutable(path: executablePath, name: app.name, identifier: app.bundleIdentifier)
        }
    }

    func activate(bundleIdentifier: String) -> ActivationResult {
        guard let app = applicationProvider.runningApplication(bundleIdentifier: bundleIdentifier) else {
            return .appNotRunning(bundleIdentifier: bundleIdentifier)
        }

        let appName = app.localizedName ?? bundleIdentifier
        switch helperRegistrationService.ensureRegistered() {
        case .available:
            break
        case .unavailable(let reason):
            return .helperUnavailable(reason: reason)
        }

        switch helperClient.raiseWindows(bundleIdentifier: bundleIdentifier) {
        case .raised(let helperAppName, _):
            return .success(appName: helperAppName)
        case .appNotRunning:
            return .appNotRunning(bundleIdentifier: bundleIdentifier)
        case .accessibilityPermissionMissing:
            return .accessibilityPermissionMissing(appName: appName)
        case .noWindowsFound(let helperAppName):
            return .noWindowsFound(appName: helperAppName)
        case .raiseFailed(let helperAppName):
            return .windowRaiseFailed(appName: helperAppName)
        case .helperUnavailable:
            let activated = app.activate(options: [.activateAllWindows])
            return activated
                ? .success(appName: appName)
                : .helperUnavailable(reason: L10n.string("activation.reason.windowHelperFallbackFailed"))
        }
    }

    private func activateExecutable(path: String, name: String, identifier: String) -> ActivationResult {
        guard let app = applicationProvider.runningApplication(executablePath: path) else {
            return .appNotRunning(bundleIdentifier: identifier)
        }

        let appName = app.localizedName ?? name
        return app.activate(options: [.activateAllWindows])
            ? .success(appName: appName)
            : .activationFailed(appName: appName)
    }
}

extension NSRunningApplication: ActivatableApplication {}

private struct NSWorkspaceApplicationProvider: ApplicationProviding {
    func runningApplication(bundleIdentifier: String) -> ActivatableApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleIdentifier
        }
    }

    func runningApplication(executablePath: String) -> ActivatableApplication? {
        let standardizedPath = URL(fileURLWithPath: executablePath).standardizedFileURL.path
        let executableApps = RunningAppService.executableAppsFromVisibleWindows(excludingProcessIDs: [])
        guard
            let runningApp = executableApps.first(where: {
                $0.executableURL?.path == standardizedPath
            }),
            let processIdentifier = runningApp.processIdentifier
        else {
            return nil
        }

        return NSRunningApplication(processIdentifier: processIdentifier)
    }
}

enum WindowHelperBundleDiagnostics {
    static var helperURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LoginItems", isDirectory: true)
            .appendingPathComponent("GatherAppsWindowHelper.app", isDirectory: true)
    }

    static func notFoundReason() -> String {
        let helperURL = Self.helperURL
        let infoPlistURL = helperURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        let helperBundle = Bundle(url: helperURL)
        let helperExists = FileManager.default.fileExists(atPath: helperURL.path)
        let infoPlistExists = FileManager.default.fileExists(atPath: infoPlistURL.path)
        let embeddedIdentifier = helperBundle?.bundleIdentifier ?? "unreadable"

        let diagnostics = [
            "GatherAppsWindowHelper login item was not found in the app bundle.",
            "Expected identifier: \(WindowHelperConfiguration.loginItemIdentifier).",
            "Main bundle: \(Bundle.main.bundleURL.path).",
            "Expected helper path: \(helperURL.path).",
            "Helper exists: \(helperExists).",
            "Helper Info.plist exists: \(infoPlistExists).",
            "Embedded helper identifier: \(embeddedIdentifier)."
        ].joined(separator: "\n")

        let diagnosticsFilePath = writeDiagnostics(diagnostics)

        return [
            L10n.string("activation.reason.loginItemNotFound"),
            "helperExists=\(helperExists)",
            "embeddedID=\(embeddedIdentifier)",
            "diagnostics=\(diagnosticsFilePath ?? "write-failed")"
        ].joined(separator: " ")
    }

    static func urlsReferToSameBundle(_ lhs: URL, _ rhs: URL) -> Bool {
        canonicalURL(lhs) == canonicalURL(rhs)
    }

    static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func writeDiagnostics(_ diagnostics: String) -> String? {
        do {
            let fileURL = try AppSupportPaths.windowHelperDiagnosticsFileURL
            try diagnostics.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL.path
        } catch {
            return nil
        }
    }
}

enum WindowHelperOperation: String {
    case raiseWindows
    case probe
    case requestAccessibilityPermission
}

enum WindowHelperNotification {
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

struct NotificationWindowHelperClient: WindowHelperClient {
    private let timeout: TimeInterval
    private let expectedHelperURL: URL

    init(
        timeout: TimeInterval = 2,
        expectedHelperURL: URL = WindowHelperBundleDiagnostics.helperURL
    ) {
        self.timeout = timeout
        self.expectedHelperURL = expectedHelperURL
    }

    func raiseWindows(bundleIdentifier: String) -> WindowHelperActivationResult {
        send(operation: .raiseWindows, bundleIdentifier: bundleIdentifier)?.activationResult
            ?? .helperUnavailable(reason: L10n.string("activation.reason.helperDidNotRespond"))
    }

    func probe() -> WindowHelperRuntimeInfo? {
        send(operation: .probe)?.runtimeInfo
    }

    func requestAccessibilityPermission() -> WindowHelperRuntimeInfo? {
        send(operation: .requestAccessibilityPermission)?.runtimeInfo
    }

    private func send(
        operation: WindowHelperOperation,
        bundleIdentifier: String? = nil
    ) -> WindowHelperProcessResult? {
        let center = DistributedNotificationCenter.default()
        let requestID = UUID().uuidString
        var response: WindowHelperProcessResult?

        let observer = center.addObserver(
            forName: WindowHelperNotification.response,
            object: nil,
            queue: .main
        ) { notification in
            guard
                let userInfo = notification.userInfo,
                userInfo[WindowHelperNotification.requestIDKey] as? String == requestID
            else {
                return
            }

            let candidate = WindowHelperProcessResult(userInfo: userInfo)
            guard
                candidate.protocolVersion == WindowHelperConfiguration.protocolVersion,
                let helperBundleURL = candidate.helperBundleURL,
                WindowHelperBundleDiagnostics.urlsReferToSameBundle(helperBundleURL, expectedHelperURL)
            else {
                return
            }

            response = candidate
        }

        defer {
            center.removeObserver(observer)
        }

        var userInfo: [String: Any] = [
            WindowHelperNotification.requestIDKey: requestID,
            WindowHelperNotification.operationKey: operation.rawValue,
            WindowHelperNotification.protocolVersionKey: WindowHelperConfiguration.protocolVersion
        ]
        if let bundleIdentifier {
            userInfo[WindowHelperNotification.bundleIdentifierKey] = bundleIdentifier
        }

        center.postNotificationName(
            WindowHelperNotification.request,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )

        let deadline = Date().addingTimeInterval(timeout)
        while response == nil, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        return response
    }
}

struct WindowHelperProcessResult {
    let bundleIdentifier: String
    let appName: String?
    let status: String
    let raisedWindowCount: Int?
    let message: String?
    let helperBundlePath: String?
    let protocolVersion: Int
    let accessibilityTrusted: Bool?

    init(userInfo: [AnyHashable: Any]) {
        bundleIdentifier = userInfo[WindowHelperNotification.bundleIdentifierKey] as? String ?? ""
        appName = userInfo[WindowHelperNotification.appNameKey] as? String
        status = userInfo[WindowHelperNotification.statusKey] as? String ?? "helperUnavailable"
        raisedWindowCount = userInfo[WindowHelperNotification.raisedWindowCountKey] as? Int
        message = userInfo[WindowHelperNotification.messageKey] as? String
        helperBundlePath = userInfo[WindowHelperNotification.helperBundlePathKey] as? String
        protocolVersion = userInfo[WindowHelperNotification.protocolVersionKey] as? Int ?? 0
        accessibilityTrusted = userInfo[WindowHelperNotification.accessibilityTrustedKey] as? Bool
    }

    var helperBundleURL: URL? {
        helperBundlePath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var runtimeInfo: WindowHelperRuntimeInfo? {
        guard let helperBundleURL, let accessibilityTrusted else { return nil }
        return WindowHelperRuntimeInfo(
            bundleURL: helperBundleURL,
            protocolVersion: protocolVersion,
            accessibilityTrusted: accessibilityTrusted
        )
    }

    var activationResult: WindowHelperActivationResult {
        switch status {
        case "raised":
            return .raised(appName: appName ?? bundleIdentifier, raisedWindowCount: raisedWindowCount ?? 0)
        case "appNotRunning":
            return .appNotRunning(bundleIdentifier: bundleIdentifier)
        case "accessibilityPermissionMissing":
            return .accessibilityPermissionMissing
        case "noWindowsFound":
            return .noWindowsFound(appName: appName ?? bundleIdentifier)
        case "raiseFailed":
            return .raiseFailed(appName: appName ?? bundleIdentifier)
        default:
            return .helperUnavailable(
                reason: message ?? L10n.format("activation.reason.unrecognizedHelperStatus", status)
            )
        }
    }
}
