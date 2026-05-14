import Combine
import Foundation

@MainActor
final class AppGroupStore: ObservableObject {
    @Published private(set) var groups: [AppGroup] = []
    @Published var lastActivationResults: [ActivationResult] = []
    @Published var lastLauncherGenerationResult: LauncherGenerationResult?
    @Published var lastErrorMessage: String?

    private let groupsFileURL: URL?
    private let iconService = GroupIconService()
    private let activationService = AppActivationService()
    private let launcherGeneratorService: LauncherAppGeneratorService

    init(
        groupsFileURL: URL? = nil,
        launcherGeneratorService: LauncherAppGeneratorService? = nil
    ) {
        self.groupsFileURL = groupsFileURL
        self.launcherGeneratorService = launcherGeneratorService ?? LauncherAppGeneratorService()
        load()
        regenerateMissingIcons()
    }

    func createGroup(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        var group = AppGroup(name: trimmedName)
        do {
            group.iconFileName = try iconService.generateIcon(for: group)
            groups.append(group)
            save()
        } catch {
            lastErrorMessage = "그룹 아이콘을 생성하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func deleteGroups(at offsets: IndexSet) {
        let removedGroups = offsets.map { groups[$0] }
        for index in offsets.sorted(by: >) {
            groups.remove(at: index)
        }
        for group in removedGroups {
            deleteResources(for: group)
        }
        save()
    }

    func deleteGroup(id: AppGroup.ID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        let group = groups.remove(at: index)
        deleteResources(for: group)
        save()
    }

    func add(_ runningApp: RunningAppInfo, to groupID: AppGroup.ID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard !groups[index].apps.contains(where: { $0.bundleIdentifier == runningApp.bundleIdentifier }) else {
            return
        }

        groups[index].apps.append(
            GroupedApp(
                bundleIdentifier: runningApp.bundleIdentifier,
                name: runningApp.name,
                appPath: runningApp.appURL.path
            )
        )
        regenerateIcon(forGroupAt: index)
    }

    func removeApps(at offsets: IndexSet, from groupID: AppGroup.ID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        for appIndex in offsets.sorted(by: >) {
            groups[index].apps.remove(at: appIndex)
        }
        regenerateIcon(forGroupAt: index)
    }

    func activate(groupID: AppGroup.ID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        lastActivationResults = group.apps.map {
            activationService.activate(bundleIdentifier: $0.bundleIdentifier)
        }
    }

    func handleActivationURL(_ url: URL) -> AppGroup.ID? {
        guard let groupID = GatherTabURLScheme.groupID(from: url) else {
            return nil
        }

        activate(groupID: groupID)
        return groupID
    }

    func generateLauncher(for groupID: AppGroup.ID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }

        do {
            lastLauncherGenerationResult = try launcherGeneratorService.generateLauncher(for: group)
        } catch {
            lastErrorMessage = "런처 앱을 생성하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func iconImageURL(for group: AppGroup) -> URL? {
        guard let iconFileName = group.iconFileName else { return nil }
        return iconService.iconURL(for: iconFileName)
    }

    private func load() {
        do {
            let fileURL = try groupsFileURL ?? AppSupportPaths.groupsFileURL
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                groups = []
                return
            }

            let data = try Data(contentsOf: fileURL)
            groups = try JSONDecoder().decode([AppGroup].self, from: data)
        } catch {
            groups = []
            lastErrorMessage = "그룹 목록을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            let fileURL = try groupsFileURL ?? AppSupportPaths.groupsFileURL
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(groups)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            lastErrorMessage = "그룹 목록을 저장하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func regenerateMissingIcons() {
        var didChange = false
        for index in groups.indices {
            guard groups[index].iconFileName == nil else { continue }
            do {
                groups[index].iconFileName = try iconService.generateIcon(for: groups[index])
                didChange = true
            } catch {
                lastErrorMessage = "그룹 아이콘을 생성하지 못했습니다: \(error.localizedDescription)"
            }
        }

        if didChange {
            save()
        }
    }

    private func regenerateIcon(forGroupAt index: Int) {
        do {
            let previousIconFileName = groups[index].iconFileName
            let newIconFileName = try iconService.generateIcon(for: groups[index])
            groups[index].iconFileName = newIconFileName
            save()
            if let previousIconFileName, previousIconFileName != newIconFileName {
                deleteIcon(named: previousIconFileName)
            }
        } catch {
            lastErrorMessage = "그룹 아이콘을 갱신하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func deleteResources(for group: AppGroup) {
        deleteIcon(for: group)
        do {
            try launcherGeneratorService.deleteLauncher(for: group)
        } catch {
            lastErrorMessage = "런처 앱을 삭제하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func deleteIcon(for group: AppGroup) {
        guard let iconFileName = group.iconFileName, let iconURL = iconService.iconURL(for: iconFileName) else {
            return
        }

        try? FileManager.default.removeItem(at: iconURL)
    }

    private func deleteIcon(named fileName: String) {
        guard let iconURL = iconService.iconURL(for: fileName) else {
            return
        }

        try? FileManager.default.removeItem(at: iconURL)
    }
}
