import Foundation

struct StatusBarGroupMenuItem: Equatable {
    let groupID: AppGroup.ID
    let title: String
    let runningCountTitle: String
    let isEnabled: Bool
}

enum StatusBarMenuModel {
    static func groupItems(
        for groups: [AppGroup],
        runningAppIdentifiers: Set<String>
    ) -> [StatusBarGroupMenuItem] {
        groups.map { group in
            let runningCount = group.apps.filter {
                runningAppIdentifiers.contains($0.id)
            }.count
            let totalCount = group.apps.count

            return StatusBarGroupMenuItem(
                groupID: group.id,
                title: "Activate \(group.name)",
                runningCountTitle: "\(runningCount)/\(totalCount) running",
                isEnabled: !group.apps.isEmpty
            )
        }
    }
}
