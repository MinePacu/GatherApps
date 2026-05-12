import AppKit
import Foundation

struct RunningAppService {
    func fetchRunningApps() -> [RunningAppInfo] {
        let apps: [RunningAppInfo] = NSWorkspace.shared.runningApplications
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

        return Self.uniqueApps(apps)
    }

    static func uniqueApps(_ apps: [RunningAppInfo]) -> [RunningAppInfo] {
        var seenBundleIdentifiers = Set<String>()

        return apps
            .filter { app in
                seenBundleIdentifiers.insert(app.bundleIdentifier).inserted
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func icon(for app: RunningAppInfo) -> NSImage {
        NSWorkspace.shared.icon(forFile: app.appURL.path)
    }
}
