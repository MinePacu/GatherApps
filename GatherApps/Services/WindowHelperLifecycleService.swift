import AppKit
import Foundation
import ServiceManagement

struct WindowHelperProcess: Equatable {
    let processIdentifier: pid_t
    let bundleURL: URL?
}

protocol WindowHelperLoginItemServicing {
    var status: SMAppService.Status { get }

    func register() throws
    func unregister() throws
}

protocol WindowHelperProcessControlling {
    var runningHelpers: [WindowHelperProcess] { get }

    func terminate(processIdentifiers: [pid_t])
    func launchHelper(at url: URL) -> Error?
}

struct SystemWindowHelperLoginItemService: WindowHelperLoginItemServicing {
    private var service: SMAppService {
        SMAppService.loginItem(identifier: WindowHelperConfiguration.loginItemIdentifier)
    }

    var status: SMAppService.Status {
        service.status
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}

struct WorkspaceWindowHelperProcessController: WindowHelperProcessControlling {
    var runningHelpers: [WindowHelperProcess] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.bundleIdentifier == WindowHelperConfiguration.loginItemIdentifier else {
                return nil
            }
            return WindowHelperProcess(
                processIdentifier: app.processIdentifier,
                bundleURL: app.bundleURL
            )
        }
    }

    func terminate(processIdentifiers: [pid_t]) {
        let identifiers = Set(processIdentifiers)
        NSWorkspace.shared.runningApplications
            .filter { identifiers.contains($0.processIdentifier) }
            .forEach { $0.terminate() }
    }

    func launchHelper(at url: URL) -> Error? {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        var launchError: Error?
        var didComplete = false

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            launchError = error
            didComplete = true
        }

        let deadline = Date().addingTimeInterval(2)
        while !didComplete, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        return launchError
    }
}

struct LoginItemWindowHelperRegistrationService: WindowHelperRegistrationProviding {
    private let loginItemService: WindowHelperLoginItemServicing
    private let processController: WindowHelperProcessControlling
    private let helperURL: URL
    private let startupGracePeriod: TimeInterval
    private let transitionTimeout: TimeInterval

    init(
        loginItemService: WindowHelperLoginItemServicing = SystemWindowHelperLoginItemService(),
        processController: WindowHelperProcessControlling = WorkspaceWindowHelperProcessController(),
        helperURL: URL = WindowHelperBundleDiagnostics.helperURL,
        startupGracePeriod: TimeInterval = 0.5,
        transitionTimeout: TimeInterval = 2
    ) {
        self.loginItemService = loginItemService
        self.processController = processController
        self.helperURL = helperURL
        self.startupGracePeriod = startupGracePeriod
        self.transitionTimeout = transitionTimeout
    }

    func ensureRegistered() -> WindowHelperRegistrationResult {
        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            return .unavailable(reason: WindowHelperBundleDiagnostics.notFoundReason())
        }

        switch loginItemService.status {
        case .enabled:
            if hasStaleHelpers {
                return replaceRegistration()
            }
            if isCurrentHelperRunning || waitForCurrentHelper(timeout: startupGracePeriod) {
                return .available
            }
            return replaceRegistration()
        case .notRegistered:
            terminateAllHelpers()
            return registerCurrentHelper()
        case .requiresApproval:
            terminateStaleHelpersAndWait()
            return launchCurrentHelper(
                fallbackReason: L10n.string("activation.reason.loginItemRequiresApproval")
            )
        case .notFound:
            terminateStaleHelpersAndWait()
            return launchCurrentHelper(fallbackReason: WindowHelperBundleDiagnostics.notFoundReason())
        @unknown default:
            terminateStaleHelpersAndWait()
            return launchCurrentHelper(
                fallbackReason: L10n.string("activation.reason.loginItemUnknownStatus")
            )
        }
    }

    func restart() -> WindowHelperRegistrationResult {
        let hadStaleHelpers = hasStaleHelpers
        terminateAllHelpers()
        _ = waitUntil(timeout: transitionTimeout) { processController.runningHelpers.isEmpty }

        if loginItemService.status == .requiresApproval {
            return launchCurrentHelper(
                fallbackReason: L10n.string("activation.reason.loginItemRequiresApproval")
            )
        }

        if loginItemService.status == .enabled, !hadStaleHelpers {
            return launchCurrentHelper(
                fallbackReason: L10n.string("activation.reason.helperDidNotRespond")
            )
        }

        return replaceRegistration(helpersAlreadyTerminated: true)
    }

    private func replaceRegistration(helpersAlreadyTerminated: Bool = false) -> WindowHelperRegistrationResult {
        if !helpersAlreadyTerminated {
            terminateAllHelpers()
            _ = waitUntil(timeout: transitionTimeout) { processController.runningHelpers.isEmpty }
        }

        if loginItemService.status != .notRegistered {
            do {
                try loginItemService.unregister()
                _ = waitUntil(timeout: transitionTimeout) {
                    loginItemService.status == .notRegistered
                }
            } catch {
                return launchCurrentHelper(fallbackReason: error.localizedDescription)
            }
        }

        return registerCurrentHelper()
    }

    private func registerCurrentHelper() -> WindowHelperRegistrationResult {
        do {
            try loginItemService.register()
        } catch {
            return launchCurrentHelper(fallbackReason: error.localizedDescription)
        }

        if loginItemService.status == .enabled,
           waitForCurrentHelper(timeout: transitionTimeout) {
            terminateStaleHelpers()
            return .available
        }

        let reason = loginItemService.status == .requiresApproval
            ? L10n.string("activation.reason.loginItemApprovalPending")
            : L10n.string("activation.reason.helperDidNotRespond")
        return launchCurrentHelper(fallbackReason: reason)
    }

    private func launchCurrentHelper(fallbackReason: String) -> WindowHelperRegistrationResult {
        if isCurrentHelperRunning {
            return .available
        }

        if let error = processController.launchHelper(at: helperURL) {
            return .unavailable(
                reason: L10n.format(
                    "activation.reason.helperLaunchFailed",
                    fallbackReason,
                    error.localizedDescription
                )
            )
        }

        return waitForCurrentHelper(timeout: transitionTimeout)
            ? .available
            : .unavailable(
                reason: L10n.format("activation.reason.helperLaunchDidNotStart", fallbackReason)
            )
    }

    private var isCurrentHelperRunning: Bool {
        processController.runningHelpers.contains { process in
            guard let bundleURL = process.bundleURL else { return false }
            return WindowHelperBundleDiagnostics.urlsReferToSameBundle(bundleURL, helperURL)
        }
    }

    private var hasStaleHelpers: Bool {
        processController.runningHelpers.contains { process in
            guard let bundleURL = process.bundleURL else { return true }
            return !WindowHelperBundleDiagnostics.urlsReferToSameBundle(bundleURL, helperURL)
        }
    }

    private func terminateStaleHelpers() {
        let identifiers = processController.runningHelpers.compactMap { process -> pid_t? in
            guard let bundleURL = process.bundleURL else { return process.processIdentifier }
            return WindowHelperBundleDiagnostics.urlsReferToSameBundle(bundleURL, helperURL)
                ? nil
                : process.processIdentifier
        }
        guard !identifiers.isEmpty else { return }
        processController.terminate(processIdentifiers: identifiers)
    }

    private func terminateStaleHelpersAndWait() {
        terminateStaleHelpers()
        _ = waitUntil(timeout: transitionTimeout) { !hasStaleHelpers }
    }

    private func terminateAllHelpers() {
        processController.terminate(
            processIdentifiers: processController.runningHelpers.map(\.processIdentifier)
        )
    }

    private func waitForCurrentHelper(timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) { isCurrentHelperRunning }
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        if condition() {
            return true
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if condition() {
                return true
            }
        }
        return condition()
    }
}
