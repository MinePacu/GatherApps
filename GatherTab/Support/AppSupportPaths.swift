import Foundation

enum AppSupportPaths {
    static let appDirectoryName = "GatherTab"

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
            return directory
        }
    }

    static var groupsFileURL: URL {
        get throws {
            try appSupportDirectory.appendingPathComponent("groups.json")
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
}
