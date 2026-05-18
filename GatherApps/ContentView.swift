import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AppGroupStore
    let showSwitcher: () -> Void
    let handleActivationURL: (URL) -> Void
    @State private var selectedGroupID: AppGroup.ID?
    @State private var isShowingCreateGroup = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                store: store,
                selection: $selectedGroupID,
                onCreateGroup: { isShowingCreateGroup = true }
            )
        } detail: {
            if let selectedGroupID {
                GroupDetailView(store: store, groupID: selectedGroupID)
            } else {
                ContentUnavailableView("content.noGroupSelected", systemImage: "square.grid.2x2")
            }
        }
        .frame(
            minWidth: AppLayout.minimumWindowWidth,
            idealWidth: AppLayout.defaultWindowWidth,
            minHeight: AppLayout.minimumWindowHeight,
            idealHeight: AppLayout.defaultWindowHeight
        )
        .toolbar {
            ToolbarItem {
                Button(role: .destructive, action: deleteSelectedGroup) {
                    Label("sidebar.deleteGroup", systemImage: "trash")
                }
                .disabled(selectedGroupID == nil)
            }

            ToolbarItem {
                Button {
                    showSwitcher()
                } label: {
                    Label("content.openSwitcher", systemImage: "square.grid.2x2")
                }
            }
        }
        .onAppear {
            selectedGroupID = selectedGroupID ?? store.groups.first?.id
        }
        .onOpenURL { url in
            if let groupID = GatherAppsURLScheme.groupID(from: url) {
                handleActivationURL(url)
                if GatherAppsURLScheme.showsGatherAppsWindow(from: url) {
                    selectedGroupID = groupID
                } else {
                    NSApp.hide(nil)
                }
            }
        }
        .sheet(isPresented: $isShowingCreateGroup) {
            CreateGroupSheet { name in
                store.createGroup(named: name)
                selectedGroupID = store.groups.last?.id
            }
        }
        .alert(
            "common.error",
            isPresented: Binding(
                get: { store.lastErrorMessage != nil },
                set: { if !$0 { store.lastErrorMessage = nil } }
            )
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(store.lastErrorMessage ?? "")
        }
    }

    private func deleteSelectedGroup() {
        guard let deletedGroupID = selectedGroupID else { return }

        store.deleteGroup(id: deletedGroupID)
        selectedGroupID = ContentSelection.selection(
            afterDeleting: deletedGroupID,
            currentSelection: selectedGroupID,
            remainingGroupIDs: store.groups.map(\.id)
        )
    }
}

enum AppLayout {
    static let minimumWindowWidth: CGFloat = 1040
    static let defaultWindowWidth: CGFloat = 1160
    static let minimumWindowHeight: CGFloat = 540
    static let defaultWindowHeight: CGFloat = 640
}

enum ContentSelection {
    static func selection(
        afterDeleting deletedGroupID: AppGroup.ID,
        currentSelection: AppGroup.ID?,
        remainingGroupIDs: [AppGroup.ID]
    ) -> AppGroup.ID? {
        guard currentSelection == deletedGroupID else {
            return currentSelection
        }

        return remainingGroupIDs.first
    }
}
