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
            "\(appName)을 활성화했습니다."
        case .appNotRunning:
            "실행 중인 앱을 찾을 수 없습니다."
        case .accessibilityPermissionMissing(let appName):
            "\(appName) 창을 가져오려면 GatherTabWindowHelper의 손쉬운 사용 권한이 필요합니다."
        case .helperUnavailable(let reason):
            "창 제어 도우미를 실행하지 못했습니다. \(reason)"
        case .noWindowsFound(let appName):
            "\(appName)의 표시 가능한 창을 찾지 못했습니다."
        case .windowRaiseFailed(let appName):
            "\(appName) 창을 앞으로 가져오지 못했습니다."
        case .activationFailed(let appName):
            "\(appName)을 활성화하지 못했습니다."
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
