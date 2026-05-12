import Foundation

enum ActivationResult: Equatable {
    case success(appName: String)
    case appNotRunning(bundleIdentifier: String)
    case activationFailed(appName: String)

    var message: String {
        switch self {
        case .success(let appName):
            "\(appName)을 활성화했습니다."
        case .appNotRunning:
            "실행 중인 앱을 찾을 수 없습니다."
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
