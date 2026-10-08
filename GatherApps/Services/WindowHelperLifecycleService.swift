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
    func launchHelper(at url: URL) async -> Error?
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

    func launchHelper(at url: URL) async -> Error? {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        let waiter = OneShotTimeoutWaiter<Error?>()

        // The completion handler runs on a background queue; hop to the main actor to deliver it.
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { @Sendable _, error in
            Task { @MainActor in
                waiter.finish(error)
            }
        }

        return await waiter.wait(timeout: 2, timeoutValue: nil)
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

    func ensureRegistered() async -> WindowHelperRegistrationResult {
        await WindowHelperLifecycleSerializer.run { await performEnsureRegistered() }
    }

    func restart() async -> WindowHelperRegistrationResult {
        await WindowHelperLifecycleSerializer.run { await performRestart() }
    }

    // The perform methods run inside the serializer and must only call private helpers;
    // calling `ensureRegistered()` or `restart()` from here would wait on itself forever.
    private func performEnsureRegistered() async -> WindowHelperRegistrationResult {
        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            return .unavailable(reason: WindowHelperBundleDiagnostics.notFoundReason())
        }

        switch loginItemService.status {
        case .enabled:
            if hasStaleHelpers {
                return await replaceRegistration()
            }
            if isCurrentHelperRunning {
                return .available
            }
            if await waitForCurrentHelper(timeout: startupGracePeriod) {
                return .available
            }
            return await replaceRegistration()
        case .notRegistered:
            terminateAllHelpers()
            return await registerCurrentHelper()
        case .notFound:
            await terminateStaleHelpersAndWait()
            if isCurrentHelperRunning {
                return .available
            }
            return await registerCurrentHelper()
        case .requiresApproval:
            await terminateStaleHelpersAndWait()
            return await launchCurrentHelper(
                fallbackReason: L10n.string("activation.reason.loginItemRequiresApproval")
            )
        @unknown default:
            await terminateStaleHelpersAndWait()
            return await launchCurrentHelper(
                fallbackReason: L10n.string("activation.reason.loginItemUnknownStatus")
            )
        }
    }

    private func performRestart() async -> WindowHelperRegistrationResult {
        let hadStaleHelpers = hasStaleHelpers
        terminateAllHelpers()
        _ = await waitUntil(timeout: transitionTimeout) { processController.runningHelpers.isEmpty }

        if loginItemService.status == .requiresApproval {
            return await launchCurrentHelper(
                fallbackReason: L10n.string("activation.reason.loginItemRequiresApproval")
            )
        }

        if loginItemService.status == .enabled, !hadStaleHelpers {
            return await launchCurrentHelper(
                fallbackReason: L10n.string("activation.reason.helperDidNotRespond")
            )
        }

        return await replaceRegistration(helpersAlreadyTerminated: true)
    }

    private func replaceRegistration(helpersAlreadyTerminated: Bool = false) async -> WindowHelperRegistrationResult {
        if !helpersAlreadyTerminated {
            terminateAllHelpers()
            _ = await waitUntil(timeout: transitionTimeout) { processController.runningHelpers.isEmpty }
        }

        if loginItemService.status != .notRegistered {
            do {
                try loginItemService.unregister()
                _ = await waitUntil(timeout: transitionTimeout) {
                    loginItemService.status == .notRegistered
                }
            } catch {
                return await launchCurrentHelper(fallbackReason: error.localizedDescription)
            }
        }

        return await registerCurrentHelper()
    }

    private func registerCurrentHelper() async -> WindowHelperRegistrationResult {
        do {
            try loginItemService.register()
        } catch {
            return await launchCurrentHelper(fallbackReason: error.localizedDescription)
        }

        if loginItemService.status == .enabled,
           await waitForCurrentHelper(timeout: transitionTimeout) {
            terminateStaleHelpers()
            return .available
        }

        let reason = loginItemService.status == .requiresApproval
            ? L10n.string("activation.reason.loginItemApprovalPending")
            : L10n.string("activation.reason.helperDidNotRespond")
        return await launchCurrentHelper(fallbackReason: reason)
    }

    private func launchCurrentHelper(fallbackReason: String) async -> WindowHelperRegistrationResult {
        if isCurrentHelperRunning {
            return .available
        }

        if let error = await processController.launchHelper(at: helperURL) {
            return .unavailable(
                reason: L10n.format(
                    "activation.reason.helperLaunchFailed",
                    fallbackReason,
                    error.localizedDescription
                )
            )
        }

        return await waitForCurrentHelper(timeout: transitionTimeout)
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

    private func terminateStaleHelpersAndWait() async {
        terminateStaleHelpers()
        _ = await waitUntil(timeout: transitionTimeout) { !hasStaleHelpers }
    }

    private func terminateAllHelpers() {
        processController.terminate(
            processIdentifiers: processController.runningHelpers.map(\.processIdentifier)
        )
    }

    private func waitForCurrentHelper(timeout: TimeInterval) async -> Bool {
        await waitUntil(timeout: timeout) { isCurrentHelperRunning }
    }

    /// Polls `condition` every 10 ms; sleeping suspends instead of blocking the main actor.
    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) async -> Bool {
        if condition() {
            return true
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(10))
            if condition() {
                return true
            }
        }
        return condition()
    }
}
