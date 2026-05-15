import Foundation

enum ActivationResult: Equatable {
    case success(appName: String)
    case appNotRunning(bundleIdentifier: String)
    case accessibilityPermissionMissing(appName: String)
    case helperUnavailable(reason: String)
    case noWindowsFound(appName: String)
    case windowRaiseFailed(appName: String)
    case activationFailed(appName: String)

    var message: String {
        switch self {
        case .success(let appName):
            L10n.format("activation.success", appName)
        case .appNotRunning:
            L10n.string("activation.appNotRunning")
        case .accessibilityPermissionMissing(let appName):
            L10n.format("activation.accessibilityPermissionMissing", appName)
        case .helperUnavailable(let reason):
            L10n.format("activation.helperUnavailable", reason)
        case .noWindowsFound(let appName):
            L10n.format("activation.noWindowsFound", appName)
        case .windowRaiseFailed(let appName):
            L10n.format("activation.windowRaiseFailed", appName)
        case .activationFailed(let appName):
            L10n.format("activation.activationFailed", appName)
        }
    }

    var isSuccess: Bool {
        if case .success = self {
            true
        } else {
            false
        }
    }
}
