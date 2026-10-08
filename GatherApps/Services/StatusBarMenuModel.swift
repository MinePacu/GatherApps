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
                title: L10n.format("statusBar.activateGroup", group.name),
                runningCountTitle: L10n.format("statusBar.runningCount", runningCount, totalCount),
                isEnabled: !group.apps.isEmpty
            )
        }
    }
}
