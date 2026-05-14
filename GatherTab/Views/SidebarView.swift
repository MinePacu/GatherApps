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
                Button("삭제", role: .destructive, action: confirmDeletion)
                Button("취소", role: .cancel) {
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
                    Label("그룹 생성", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button(role: .destructive, action: deleteSelectedGroup) {
                    Label("그룹 삭제", systemImage: "trash")
                }
                .disabled(selection == nil)
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
                Text("\(group.apps.count)개 앱")
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

    private func deleteSelectedGroup() {
        guard let selection else { return }
        requestDeletion(for: [selection])
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
            return "그룹 삭제"
        }

        if pendingDeletionRequest.groupNames.count == 1, let groupName = pendingDeletionRequest.groupNames.first {
            return "\"\(groupName)\" 삭제"
        }

        return "\(pendingDeletionRequest.groupNames.count)개 그룹 삭제"
    }

    private var deletionDialogMessage: String {
        guard let pendingDeletionRequest else {
            return ""
        }

        if pendingDeletionRequest.groupNames.count == 1 {
            return "이 그룹과 생성된 GatherTab 런처를 삭제합니다. 그룹에 포함된 앱은 삭제되지 않습니다."
        }

        return "선택한 그룹과 생성된 GatherTab 런처를 삭제합니다. 그룹에 포함된 앱은 삭제되지 않습니다."
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
