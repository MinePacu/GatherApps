import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: AppGroupStore
    @Binding var selection: AppGroup.ID?
    let onCreateGroup: () -> Void

    var body: some View {
        sidebarList
            .frame(minWidth: 220, idealWidth: 260)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
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
        let selectedID = selection
        store.deleteGroups(at: offsets)
        if selectedID.map({ id in !store.groups.contains(where: { $0.id == id }) }) == true {
            selection = store.groups.first?.id
        }
    }

    private func deleteSelectedGroup() {
        guard let selection else { return }
        store.deleteGroup(id: selection)
        self.selection = store.groups.first?.id
    }
}
