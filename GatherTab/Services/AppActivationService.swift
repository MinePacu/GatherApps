import AppKit
import Foundation
import ServiceManagement

protocol ActivatableApplication {
    var bundleIdentifier: String? { get }
    var localizedName: String? { get }
    var processIdentifier: pid_t { get }

    func activate(options: NSApplication.ActivationOptions) -> Bool
}

protocol ApplicationProviding {
    func runningApplication(bundleIdentifier: String) -> ActivatableApplication?
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
}

protocol WindowHelperClient {
    func raiseWindows(bundleIdentifier: String) -> WindowHelperActivationResult
}

enum WindowHelperConfiguration {
    static let loginItemIdentifier = "com.minepacu.GatherTab.WindowHelper"
    static let notificationNamespace = loginItemIdentifier
}

struct AppActivationService {
    private let applicationProvider: ApplicationProviding
    private let helperRegistrationService: WindowHelperRegistrationProviding
    private let helperClient: WindowHelperClient

    init(
        applicationProvider: ApplicationProviding = NSWorkspaceApplicationProvider(),
        helperRegistrationService: WindowHelperRegistrationProviding = LoginItemWindowHelperRegistrationService(),
        helperClient: WindowHelperClient = DistributedNotificationWindowHelperClient()
    ) {
        self.applicationProvider = applicationProvider
        self.helperRegistrationService = helperRegistrationService
        self.helperClient = helperClient
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
            return activated ? .success(appName: appName) : .helperUnavailable(reason: "Window helper is unavailable and fallback activation failed.")
        }
    }
}

extension NSRunningApplication: ActivatableApplication {}

private struct NSWorkspaceApplicationProvider: ApplicationProviding {
    func runningApplication(bundleIdentifier: String) -> ActivatableApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleIdentifier
        }
    }
}

private struct LoginItemWindowHelperRegistrationService: WindowHelperRegistrationProviding {
    private let embeddedLauncher = EmbeddedWindowHelperLauncher()

    func ensureRegistered() -> WindowHelperRegistrationResult {
        let service = SMAppService.loginItem(identifier: WindowHelperConfiguration.loginItemIdentifier)

        switch service.status {
        case .enabled:
            return .available
        case .notRegistered:
            do {
                try service.register()
                if service.status == .enabled {
                    return .available
                }
                return embeddedLauncher.launchIfNeeded(
                    fallbackReason: "Login item registration is pending user approval."
                )
            } catch {
                return embeddedLauncher.launchIfNeeded(fallbackReason: error.localizedDescription)
            }
        case .requiresApproval:
            return embeddedLauncher.launchIfNeeded(
                fallbackReason: "Login item requires user approval in System Settings."
            )
        case .notFound:
            return embeddedLauncher.launchIfNeeded(fallbackReason: WindowHelperBundleDiagnostics.notFoundReason())
        @unknown default:
            return embeddedLauncher.launchIfNeeded(
                fallbackReason: "GatherTabWindowHelper login item has an unknown registration status."
            )
        }
    }
}

private struct EmbeddedWindowHelperLauncher {
    func launchIfNeeded(fallbackReason: String) -> WindowHelperRegistrationResult {
        if isHelperRunning {
            return .available
        }

        let helperURL = WindowHelperBundleDiagnostics.helperURL
        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            return .unavailable(reason: "\(fallbackReason) Embedded helper app is missing at \(helperURL.path).")
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        var launchError: Error?
        var didComplete = false

        NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration) { _, error in
            launchError = error
            didComplete = true
        }

        let launchDeadline = Date().addingTimeInterval(2)
        while !didComplete, Date() < launchDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        if let launchError {
            return .unavailable(reason: "\(fallbackReason) Direct helper launch failed: \(launchError.localizedDescription)")
        }

        let runningDeadline = Date().addingTimeInterval(2)
        while !isHelperRunning, Date() < runningDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        return isHelperRunning
            ? .available
            : .unavailable(reason: "\(fallbackReason) Direct helper launch did not start GatherTabWindowHelper.")
    }

    private var isHelperRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == WindowHelperConfiguration.loginItemIdentifier
        }
    }
}

private enum WindowHelperBundleDiagnostics {
    static var helperURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LoginItems", isDirectory: true)
            .appendingPathComponent("GatherTabWindowHelper.app", isDirectory: true)
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
            "GatherTabWindowHelper login item was not found in the app bundle.",
            "Expected identifier: \(WindowHelperConfiguration.loginItemIdentifier).",
            "Main bundle: \(Bundle.main.bundleURL.path).",
            "Expected helper path: \(helperURL.path).",
            "Helper exists: \(helperExists).",
            "Helper Info.plist exists: \(infoPlistExists).",
            "Embedded helper identifier: \(embeddedIdentifier)."
        ].joined(separator: "\n")

        let diagnosticsFilePath = writeDiagnostics(diagnostics)

        return [
            "Login item not found.",
            "helperExists=\(helperExists)",
            "embeddedID=\(embeddedIdentifier)",
            "diagnostics=\(diagnosticsFilePath ?? "write-failed")"
        ].joined(separator: " ")
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

private enum WindowHelperNotification {
    static let request = Notification.Name("\(WindowHelperConfiguration.notificationNamespace).raiseWindows.request")
    static let response = Notification.Name("\(WindowHelperConfiguration.notificationNamespace).raiseWindows.response")
    static let bundleIdentifierKey = "bundleIdentifier"
    static let requestIDKey = "requestID"
    static let appNameKey = "appName"
    static let statusKey = "status"
    static let raisedWindowCountKey = "raisedWindowCount"
    static let messageKey = "message"
}

private struct DistributedNotificationWindowHelperClient: WindowHelperClient {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 2) {
        self.timeout = timeout
    }

    func raiseWindows(bundleIdentifier: String) -> WindowHelperActivationResult {
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

            response = WindowHelperProcessResult(userInfo: userInfo)
        }

        defer {
            center.removeObserver(observer)
        }

        center.postNotificationName(
            WindowHelperNotification.request,
            object: nil,
            userInfo: [
                WindowHelperNotification.requestIDKey: requestID,
                WindowHelperNotification.bundleIdentifierKey: bundleIdentifier
            ],
            deliverImmediately: true
        )

        let deadline = Date().addingTimeInterval(timeout)
        while response == nil, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        return response?.activationResult ?? .helperUnavailable(reason: "GatherTabWindowHelper did not respond.")
    }
}

private struct WindowHelperProcessResult {
    let bundleIdentifier: String
    let appName: String?
    let status: String
    let raisedWindowCount: Int?
    let message: String?

    init(userInfo: [AnyHashable: Any]) {
        bundleIdentifier = userInfo[WindowHelperNotification.bundleIdentifierKey] as? String ?? ""
        appName = userInfo[WindowHelperNotification.appNameKey] as? String
        status = userInfo[WindowHelperNotification.statusKey] as? String ?? "helperUnavailable"
        raisedWindowCount = userInfo[WindowHelperNotification.raisedWindowCountKey] as? Int
        message = userInfo[WindowHelperNotification.messageKey] as? String
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
            return .helperUnavailable(reason: message ?? "Unrecognized helper status: \(status)")
        }
    }
}
