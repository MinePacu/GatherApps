import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AppGroupStore
    let showSwitcher: () -> Void
    let handleActivationURL: (URL) -> Void
    @State private var selectedGroupID: AppGroup.ID?
    @State private var isShowingCreateGroup = false
    @State private var deletionConfirmation = ToolbarDeletionConfirmationState()

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
                Button(role: .destructive) {
                    requestDeletion()
                } label: {
                    Label("sidebar.deleteGroup", systemImage: "trash")
                }
                .disabled(selectedGroup == nil)
            }

            ToolbarItem {
                Button {
                    showSwitcher()
                } label: {
                    Label("content.openSwitcher", systemImage: "square.grid.2x2")
                }
            }
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: isShowingDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.string("common.delete"), role: .destructive, action: confirmDeletion)
            Button(L10n.string("common.cancel"), role: .cancel) {
                deletionConfirmation.cancel()
            }
        } message: {
            Text(deleteConfirmationMessage)
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

    private func requestDeletion() {
        guard let selectedGroup else { return }
        deletionConfirmation.request(for: selectedGroup)
    }

    private func confirmDeletion() {
        deletionConfirmation.confirm { deletedGroupID in
            store.deleteGroup(id: deletedGroupID)
            selectedGroupID = ContentSelection.selection(
                afterDeleting: deletedGroupID,
                currentSelection: selectedGroupID,
                remainingGroupIDs: store.groups.map(\.id)
            )
        }
    }

    private var selectedGroup: AppGroup? {
        guard let selectedGroupID else { return nil }
        return store.groups.first { $0.id == selectedGroupID }
    }

    private var deleteConfirmationTitle: String {
        guard let pendingRequest = deletionConfirmation.pendingRequest else {
            return L10n.string("sidebar.deleteGroup")
        }

        return L10n.format("sidebar.deleteConfirmation.singleTitle", pendingRequest.groupName)
    }

    private var deleteConfirmationMessage: String {
        guard deletionConfirmation.pendingRequest != nil else { return "" }
        return L10n.string("sidebar.deleteConfirmation.singleMessage")
    }

    private var isShowingDeletionConfirmation: Binding<Bool> {
        Binding {
            deletionConfirmation.pendingRequest != nil
        } set: { isPresented in
            if !isPresented {
                deletionConfirmation.cancel()
            }
        }
    }
}

struct ToolbarDeletionRequest: Equatable {
    let groupID: AppGroup.ID
    let groupName: String

    init(group: AppGroup) {
        groupID = group.id
        groupName = group.name
    }
}

struct ToolbarDeletionConfirmationState: Equatable {
    private(set) var pendingRequest: ToolbarDeletionRequest?

    init() {
        pendingRequest = nil
    }

    mutating func request(for group: AppGroup) {
        pendingRequest = ToolbarDeletionRequest(group: group)
    }

    mutating func cancel() {
        pendingRequest = nil
    }

    mutating func confirm(delete: (AppGroup.ID) -> Void) {
        guard let pendingRequest else { return }
        self.pendingRequest = nil
        delete(pendingRequest.groupID)
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
