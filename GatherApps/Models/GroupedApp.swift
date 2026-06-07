import Foundation

enum GroupedAppKind: String, Codable {
    case bundle
    case executable
}

struct GroupedApp: Identifiable, Codable, Equatable {
    nonisolated var id: String { bundleIdentifier }

    let kind: GroupedAppKind
    let bundleIdentifier: String
    var name: String
    var appPath: String?
    var executablePath: String?

    nonisolated init(bundleIdentifier: String, name: String, appPath: String?) {
        self.kind = .bundle
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.appPath = appPath
        self.executablePath = nil
    }

    nonisolated init(executablePath: String, name: String, appPath: String?) {
        let standardizedPath = URL(fileURLWithPath: executablePath).standardizedFileURL.path
        self.kind = .executable
        self.bundleIdentifier = Self.executableIdentifier(for: standardizedPath)
        self.name = name
        self.appPath = appPath
        self.executablePath = standardizedPath
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case bundleIdentifier
        case name
        case appPath
        case executablePath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(GroupedAppKind.self, forKey: .kind) ?? .bundle
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        name = try container.decode(String.self, forKey: .name)
        appPath = try container.decodeIfPresent(String.self, forKey: .appPath)
        executablePath = try container.decodeIfPresent(String.self, forKey: .executablePath)
    }

    nonisolated static func executableIdentifier(for executablePath: String) -> String {
        "executable:\(URL(fileURLWithPath: executablePath).standardizedFileURL.path)"
    }
}
