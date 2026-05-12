import AppKit
import ApplicationServices
import Foundation

protocol ActivatableApplication {
    var bundleIdentifier: String? { get }
    var localizedName: String? { get }
    var processIdentifier: pid_t { get }

    func activate(options: NSApplication.ActivationOptions) -> Bool
}

protocol ApplicationProviding {
    func runningApplication(bundleIdentifier: String) -> ActivatableApplication?
}

protocol WindowRaising {
    var isTrusted: Bool { get }

    func raiseWindows(for processIdentifier: pid_t) -> Bool
}

struct AppActivationService {
    private let applicationProvider: ApplicationProviding
    private let windowRaiser: WindowRaising

    init(
        applicationProvider: ApplicationProviding = NSWorkspaceApplicationProvider(),
        windowRaiser: WindowRaising = AccessibilityWindowRaiser()
    ) {
        self.applicationProvider = applicationProvider
        self.windowRaiser = windowRaiser
    }

    func activate(bundleIdentifier: String) -> ActivationResult {
        guard let app = applicationProvider.runningApplication(bundleIdentifier: bundleIdentifier) else {
            return .appNotRunning(bundleIdentifier: bundleIdentifier)
        }

        let appName = app.localizedName ?? bundleIdentifier
        if windowRaiser.isTrusted, windowRaiser.raiseWindows(for: app.processIdentifier) {
            return .success(appName: appName)
        }

        let activated = app.activate(options: [.activateAllWindows])
        return activated ? .success(appName: appName) : .activationFailed(appName: appName)
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

private struct AccessibilityWindowRaiser: WindowRaising {
    var isTrusted: Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }

    func raiseWindows(for processIdentifier: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var windowsValue: CFTypeRef?
        let copyResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )

        guard
            copyResult == .success,
            let windows = windowsValue as? [AXUIElement],
            !windows.isEmpty
        else {
            return false
        }

        let raisedWindowCount = windows.reduce(0) { count, window in
            let result = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return result == .success ? count + 1 : count
        }

        return raisedWindowCount > 0
    }
}
