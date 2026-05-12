import Foundation

struct AppGroup: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var apps: [GroupedApp]
    var iconFileName: String?

    init(
        id: UUID = UUID(),
        name: String,
        apps: [GroupedApp] = [],
        iconFileName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.apps = apps
        self.iconFileName = iconFileName
    }
}
