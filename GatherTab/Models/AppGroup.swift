import Foundation

struct AppGroup: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var apps: [GroupedApp]
    var iconFileName: String?
    var launcherShowsGatherTabWindow: Bool

    init(
        id: UUID = UUID(),
        name: String,
        apps: [GroupedApp] = [],
        iconFileName: String? = nil,
        launcherShowsGatherTabWindow: Bool = false
    ) {
        self.id = id
        self.name = name
        self.apps = apps
        self.iconFileName = iconFileName
        self.launcherShowsGatherTabWindow = launcherShowsGatherTabWindow
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case apps
        case iconFileName
        case launcherShowsGatherTabWindow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        apps = try container.decode([GroupedApp].self, forKey: .apps)
        iconFileName = try container.decodeIfPresent(String.self, forKey: .iconFileName)
        launcherShowsGatherTabWindow = try container.decodeIfPresent(
            Bool.self,
            forKey: .launcherShowsGatherTabWindow
        ) ?? false
    }
}
