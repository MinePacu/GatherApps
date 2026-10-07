import Combine
import Foundation

@MainActor
final class SwitcherViewModel: ObservableObject {
    @Published private var selectedGroupID: AppGroup.ID?
    @Published private var runningAppIdentifiers: Set<String> = []

    private let store: AppGroupStore
    private let runningAppService: RunningAppService
    private var storeCancellable: AnyCancellable?
    private var lastSelectedIndex = 0
    var onDismiss: (() -> Void)?

    init(
        store: AppGroupStore,
        runningAppService: RunningAppService? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.store = store
        self.runningAppService = runningAppService ?? RunningAppService()
        self.onDismiss = onDismiss

        storeCancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        refresh()
    }

    var groups: [AppGroup] {
        store.groups
    }

    var selectedIndex: Int {
        if let selectedGroupID, let index = groups.firstIndex(where: { $0.id == selectedGroupID }) {
            return index
        }
        guard !groups.isEmpty else { return 0 }
        return min(lastSelectedIndex, groups.count - 1)
    }

    func refresh() {
        runningAppIdentifiers = Set(
            runningAppService.fetchRunningApps(includingOffscreenExecutableWindows: true).map(\.id)
        )
        clampSelection()
    }

    func moveSelectionUp() {
        guard !groups.isEmpty else { return }
        setSelectedIndex(max(selectedIndex - 1, 0))
    }

    func moveSelectionDown() {
        guard !groups.isEmpty else { return }
        setSelectedIndex(min(selectedIndex + 1, groups.count - 1))
    }

    func activateSelectedGroup() {
        guard groups.indices.contains(selectedIndex) else { return }
        activateGroup(groups[selectedIndex])
    }

    func activateGroup(_ group: AppGroup) {
        store.activate(groupID: group.id)
        dismiss()
    }

    func dismiss() {
        onDismiss?()
    }

    func isSelected(_ group: AppGroup) -> Bool {
        guard groups.indices.contains(selectedIndex) else { return false }
        return groups[selectedIndex].id == group.id
    }

    func select(_ group: AppGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        setSelectedIndex(index)
    }

    func runningAppCount(for group: AppGroup) -> Int {
        group.apps.filter {
            runningAppIdentifiers.contains($0.id)
        }.count
    }

    func iconURL(for group: AppGroup) -> URL? {
        store.iconImageURL(for: group)
    }

    private func clampSelection() {
        setSelectedIndex(selectedIndex)
    }

    private func setSelectedIndex(_ index: Int) {
        guard groups.indices.contains(index) else {
            selectedGroupID = nil
            lastSelectedIndex = 0
            return
        }
        selectedGroupID = groups[index].id
        lastSelectedIndex = index
    }
}
