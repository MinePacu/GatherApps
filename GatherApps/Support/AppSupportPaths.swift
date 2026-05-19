import Foundation

enum AppSupportPaths {
    static let appDirectoryName = "GatherApps"

    static var appSupportDirectory: URL {
        get throws {
            let baseURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = baseURL.appendingPathComponent(appDirectoryName, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try migrateLegacySandboxDataIfNeeded(to: directory)
            return directory
        }
    }

    static var groupsFileURL: URL {
        get throws {
            try appSupportDirectory.appendingPathComponent("groups.json")
        }
    }

    static var windowHelperDiagnosticsFileURL: URL {
        get throws {
            try appSupportDirectory.appendingPathComponent("window-helper-diagnostics.txt")
        }
    }

    static var iconsDirectory: URL {
        get throws {
            let directory = try appSupportDirectory
                .appendingPathComponent("Icons", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    static var launchersDirectory: URL {
        get throws {
            let directory = try appSupportDirectory
                .appendingPathComponent("Launchers", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    static var userLaunchersDirectory: URL {
        get throws {
            let baseURL = try FileManager.default.url(
                for: .applicationDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = baseURL.appendingPathComponent("GatherApps Launchers", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    private static func migrateLegacySandboxDataIfNeeded(to appSupportDirectory: URL) throws {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let legacyAppSupportDirectory = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("GatherTab", isDirectory: true)
        let legacySandboxDirectory = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent("com.minepacu.GatherTab", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("GatherTab", isDirectory: true)

        for legacyDirectory in [legacyAppSupportDirectory, legacySandboxDirectory] {
            try migrateItemIfNeeded(named: "groups.json", from: legacyDirectory, to: appSupportDirectory)
            try migrateItemIfNeeded(named: "Icons", from: legacyDirectory, to: appSupportDirectory)
        }
    }

    private static func migrateItemIfNeeded(
        named itemName: String,
        from sourceDirectory: URL,
        to destinationDirectory: URL
    ) throws {
        let sourceURL = sourceDirectory.appendingPathComponent(itemName)
        let destinationURL = destinationDirectory.appendingPathComponent(itemName)

        guard
            FileManager.default.fileExists(atPath: sourceURL.path),
            !FileManager.default.fileExists(atPath: destinationURL.path)
        else {
            return
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }
}
