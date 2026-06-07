import AppKit
import CoreGraphics
import Darwin
import Foundation

protocol WorkspaceRunningApplication {
    nonisolated var bundleIdentifier: String? { get }
    nonisolated var localizedName: String? { get }
    nonisolated var bundleURL: URL? { get }
    nonisolated var processIdentifier: pid_t { get }
}

extension NSRunningApplication: WorkspaceRunningApplication {}

struct RunningAppService {
    func fetchRunningApps() -> [RunningAppInfo] {
        let runningApplications = NSWorkspace.shared.runningApplications
        let bundledProcessIDs = Self.bundleBackedProcessIDs(from: runningApplications)
        let apps: [RunningAppInfo] = runningApplications
            .compactMap { app in
                guard
                    let bundleIdentifier = app.bundleIdentifier,
                    let name = app.localizedName,
                    let appURL = app.bundleURL
                else {
                    return nil
                }

                return RunningAppInfo(
                    bundleIdentifier: bundleIdentifier,
                    name: name,
                    appURL: appURL
                )
            }

        return Self.uniqueApps(
            apps + Self.executableAppsFromVisibleWindows(excludingProcessIDs: bundledProcessIDs)
        )
    }

    nonisolated static func uniqueApps(_ apps: [RunningAppInfo]) -> [RunningAppInfo] {
        var seenIdentifiers = Set<String>()

        return apps
            .filter { app in
                seenIdentifiers.insert(app.id).inserted
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    nonisolated static func bundleBackedProcessIDs<Application: WorkspaceRunningApplication>(
        from applications: [Application]
    ) -> Set<pid_t> {
        Set(applications.compactMap { app in
            guard
                app.bundleIdentifier != nil,
                app.localizedName != nil,
                app.bundleURL != nil
            else {
                return nil
            }

            return app.processIdentifier
        })
    }

    func icon(for app: RunningAppInfo) -> NSImage {
        NSWorkspace.shared.icon(forFile: app.appURL.path)
    }

    nonisolated static func executableAppsFromVisibleWindows(
        excludingProcessIDs excludedProcessIDs: Set<pid_t>
    ) -> [RunningAppInfo] {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return executableApps(
            from: windowInfo,
            excludingProcessIDs: excludedProcessIDs,
            executablePathForProcessID: executablePath(for:)
        )
    }

    nonisolated static func executableApps(
        from windowInfo: [[String: Any]],
        excludingProcessIDs excludedProcessIDs: Set<pid_t>,
        executablePathForProcessID: (pid_t) -> String?
    ) -> [RunningAppInfo] {
        windowInfo.compactMap { window in
            guard
                let ownerName = window[kCGWindowOwnerName as String] as? String,
                let ownerPIDNumber = window[kCGWindowOwnerPID as String] as? NSNumber,
                let layerNumber = window[kCGWindowLayer as String] as? NSNumber,
                layerNumber.intValue == 0
            else {
                return nil
            }

            let ownerPID = pid_t(ownerPIDNumber.intValue)
            guard
                !excludedProcessIDs.contains(ownerPID),
                let executablePath = executablePathForProcessID(ownerPID)
            else {
                return nil
            }

            return RunningAppInfo(
                executablePath: executablePath,
                name: ownerName,
                processIdentifier: ownerPID
            )
        }
    }

    private nonisolated static func executablePath(for processID: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(processID, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
