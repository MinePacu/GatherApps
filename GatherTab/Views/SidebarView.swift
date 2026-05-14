import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: AppGroupStore
    @Binding var selection: AppGroup.ID?
    let onCreateGroup: () -> Void

    @State private var pendingDeletionRequest: GroupDeletionRequest?

    var body: some View {
        sidebarList
            .frame(minWidth: 220, idealWidth: 260)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
            .confirmationDialog(
                deletionDialogTitle,
                isPresented: isShowingDeletionConfirmation,
                titleVisibility: .visible
            ) {
                Button(L10n.string("common.delete"), role: .destructive, action: confirmDeletion)
                Button(L10n.string("common.cancel"), role: .cancel) {
                    pendingDeletionRequest = nil
                }
            } message: {
                Text(deletionDialogMessage)
            }
    }

    private var sidebarList: some View {
        List(selection: $selection) {
            ForEach(store.groups) { group in
                sidebarRow(for: group)
                    .tag(group.id)
            }
            .onDelete(perform: deleteGroups)
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button(action: onCreateGroup) {
                    Label("sidebar.createGroup", systemImage: "plus")
                }
            }
        }
    }

    private func sidebarRow(for group: AppGroup) -> some View {
        HStack(spacing: 10) {
            GroupIconView(iconURL: store.iconImageURL(for: group), size: 28)
                .frame(width: 28, height: 28)
                .layoutPriority(1)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(L10n.format("common.appCount", group.apps.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func deleteGroups(_ offsets: IndexSet) {
        let groupIDs = offsets.compactMap { index in
            store.groups.indices.contains(index) ? store.groups[index].id : nil
        }
        requestDeletion(for: groupIDs)
    }

    private func requestDeletion(for groupIDs: [AppGroup.ID]) {
        let groups = groupIDs.compactMap { groupID in
            store.groups.first { $0.id == groupID }
        }
        guard !groups.isEmpty else { return }
        pendingDeletionRequest = GroupDeletionRequest(groups: groups)
    }

    private func confirmDeletion() {
        guard let pendingDeletionRequest else { return }
        let deletedIDs = Set(pendingDeletionRequest.groupIDs)
        for groupID in pendingDeletionRequest.groupIDs {
            store.deleteGroup(id: groupID)
        }
        if selection.map({ deletedIDs.contains($0) }) == true {
            selection = store.groups.first?.id
        }
        self.pendingDeletionRequest = nil
    }

    private var isShowingDeletionConfirmation: Binding<Bool> {
        Binding {
            pendingDeletionRequest != nil
        } set: { isPresented in
            if !isPresented {
                pendingDeletionRequest = nil
            }
        }
    }

    private var deletionDialogTitle: String {
        guard let pendingDeletionRequest else {
            return L10n.string("sidebar.deleteGroup")
        }

        if pendingDeletionRequest.groupNames.count == 1, let groupName = pendingDeletionRequest.groupNames.first {
            return L10n.format("sidebar.deleteConfirmation.singleTitle", groupName)
        }

        return L10n.format("sidebar.deleteConfirmation.multipleTitle", pendingDeletionRequest.groupNames.count)
    }

    private var deletionDialogMessage: String {
        guard let pendingDeletionRequest else {
            return ""
        }

        if pendingDeletionRequest.groupNames.count == 1 {
            return L10n.string("sidebar.deleteConfirmation.singleMessage")
        }

        return L10n.string("sidebar.deleteConfirmation.multipleMessage")
    }
}

private struct GroupDeletionRequest {
    let groupIDs: [AppGroup.ID]
    let groupNames: [String]

    init(groups: [AppGroup]) {
        self.groupIDs = groups.map(\.id)
        self.groupNames = groups.map(\.name)
    }
}
