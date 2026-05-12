import Foundation

struct GroupedApp: Identifiable, Codable, Equatable {
    var id: String { bundleIdentifier }

    let bundleIdentifier: String
    var name: String
    var appPath: String?

    init(bundleIdentifier: String, name: String, appPath: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.appPath = appPath
    }
}
