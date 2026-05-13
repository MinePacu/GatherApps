import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var store = AppGroupStore()
    @State private var selectedGroupID: AppGroup.ID?
    @State private var isShowingCreateGroup = false
    @State private var switcherWindowController = SwitcherWindowController()

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
                ContentUnavailableView("그룹을 선택하세요", systemImage: "square.grid.2x2")
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
                Button {
                    // TODO: Wire the future global shortcut service to this same entry point.
                    switcherWindowController.showSwitcher(store: store)
                } label: {
                    Label("스위처 열기", systemImage: "square.grid.2x2")
                }
            }
        }
        .onAppear {
            selectedGroupID = selectedGroupID ?? store.groups.first?.id
        }
        .onOpenURL { url in
            if let groupID = store.handleActivationURL(url) {
                if GatherTabURLScheme.showsGatherTabWindow(from: url) {
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
            "오류",
            isPresented: Binding(
                get: { store.lastErrorMessage != nil },
                set: { if !$0 { store.lastErrorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(store.lastErrorMessage ?? "")
        }
    }
}

enum AppLayout {
    static let minimumWindowWidth: CGFloat = 1040
    static let defaultWindowWidth: CGFloat = 1160
    static let minimumWindowHeight: CGFloat = 540
    static let defaultWindowHeight: CGFloat = 640
}
