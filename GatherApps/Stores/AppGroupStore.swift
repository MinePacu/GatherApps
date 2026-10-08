import Combine
import Foundation

@MainActor
final class AppGroupStore: ObservableObject {
    private enum LoadResult {
        case loaded
        case notFound
        case failed
    }

    @Published private(set) var groups: [AppGroup] = []
    @Published var lastActivationResults: [ActivationResult] = []
    @Published private(set) var lastActivationGroupID: AppGroup.ID?
    @Published var lastLauncherGenerationResult: LauncherGenerationResult?
    @Published private(set) var lastLauncherGenerationGroupID: AppGroup.ID?
    @Published var lastErrorMessage: String?
    @Published private(set) var needsAccessibilityPermission = false

    private let groupsFileURL: URL?
    private let iconService: GroupIconService
    private let iconCleanupService: GroupIconCleanupService
    private let activationService: AppActivationProviding
    private let launcherGeneratorService: LauncherAppGeneratorService
    private var isSavingBlockedByUnreadableGroupsFile = false
    /// The most recently requested activation; each new one waits for it so activations never overlap.
    private var activationTask: Task<Void, Never>?

    init(
        groupsFileURL: URL? = nil,
        iconService: GroupIconService? = nil,
        iconCleanupService: GroupIconCleanupService? = nil,
        activationService: AppActivationProviding? = nil,
        launcherGeneratorService: LauncherAppGeneratorService? = nil
    ) {
        self.groupsFileURL = groupsFileURL
        self.iconService = iconService ?? GroupIconService()
        self.iconCleanupService = iconCleanupService ?? GroupIconCleanupService()
        self.activationService = activationService ?? AppActivationService()
        self.launcherGeneratorService = launcherGeneratorService ?? LauncherAppGeneratorService()
        switch load() {
        case .loaded:
            regenerateMissingOrDeletedIcons()
            cleanupOrphanedIcons()
            regenerateStaleLaunchers()
        case .notFound, .failed:
            break
        }
    }

    @discardableResult
    func createGroup(named name: String) -> AppGroup.ID? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        var group = AppGroup(name: trimmedName)
        do {
            group.iconFileName = try iconService.generateIcon(for: group)
            groups.append(group)
            save()
            return group.id
        } catch {
            lastErrorMessage = L10n.format("errors.groupIconCreationFailed", error.localizedDescription)
            return nil
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
        cleanupOrphanedIcons()
    }

    func deleteGroup(id: AppGroup.ID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        let group = groups.remove(at: index)
        deleteResources(for: group)
        save()
        cleanupOrphanedIcons()
    }

    func add(_ runningApp: RunningAppInfo, to groupID: AppGroup.ID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard !groups[index].apps.contains(where: { $0.id == runningApp.id }) else {
            return
        }

        let groupedApp: GroupedApp
        switch runningApp.kind {
        case .bundle:
            groupedApp = GroupedApp(
                bundleIdentifier: runningApp.bundleIdentifier,
                name: runningApp.name,
                appPath: runningApp.appURL.path
            )
        case .executable:
            let executablePath = runningApp.executableURL?.path ?? runningApp.appURL.path
            groupedApp = GroupedApp(
                executablePath: executablePath,
                name: runningApp.name,
                appPath: nil
            )
        }

        groups[index].apps.append(groupedApp)
        regenerateIcon(forGroupAt: index)
    }

    func removeApps(at offsets: IndexSet, from groupID: AppGroup.ID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        for appIndex in offsets.sorted(by: >) {
            groups[index].apps.remove(at: appIndex)
        }
        regenerateIcon(forGroupAt: index)
    }

    func activate(groupID: AppGroup.ID) async {
        let previousActivation = activationTask
        let activation = Task {
            await previousActivation?.value
            await performActivation(groupID: groupID)
        }
        activationTask = activation
        await activation.value
    }

    private func performActivation(groupID: AppGroup.ID) async {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        var resultsByIdentifier: [String: ActivationResult] = [:]
        let orderedApps = Self.frontmostActivationOrder(for: group)
        let results = await activationService.activateGroup(orderedApps)

        for (app, result) in zip(orderedApps, results) {
            resultsByIdentifier[app.id] = result
        }

        lastActivationResults = group.apps.compactMap {
            resultsByIdentifier[$0.id]
        }
        lastActivationGroupID = groupID
        updateAccessibilityPermissionWarning(for: results)
    }

    func clearAccessibilityPermissionWarning() {
        needsAccessibilityPermission = false
    }

    func handleActivationURL(_ url: URL) async -> AppGroup.ID? {
        guard let groupID = GatherAppsURLScheme.groupID(from: url) else {
            return nil
        }

        await activate(groupID: groupID)
        return groupID
    }

    func generateLauncher(for groupID: AppGroup.ID, showsGatherAppsWindow: Bool = false) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }

        groups[index].launcherShowsGatherAppsWindow = showsGatherAppsWindow
        save()

        // Clear any previous result so a failed generation never shows an older success.
        lastLauncherGenerationResult = nil
        lastLauncherGenerationGroupID = groupID

        do {
            lastLauncherGenerationResult = try launcherGeneratorService.generateLauncher(
                for: groups[index],
                showsGatherAppsWindow: showsGatherAppsWindow
            )
        } catch {
            lastErrorMessage = L10n.format("errors.launcherGenerationFailed", error.localizedDescription)
        }
    }

    func setLauncherShowsGatherAppsWindow(_ showsGatherAppsWindow: Bool, for groupID: AppGroup.ID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard groups[index].launcherShowsGatherAppsWindow != showsGatherAppsWindow else { return }
        groups[index].launcherShowsGatherAppsWindow = showsGatherAppsWindow
        save()
    }

    func iconImageURL(for group: AppGroup) -> URL? {
        guard let iconFileName = group.iconFileName else { return nil }
        return iconService.iconURL(for: iconFileName)
    }

    private func load() -> LoadResult {
        let fileURL: URL
        do {
            fileURL = try groupsFileURL ?? AppSupportPaths.groupsFileURL
        } catch {
            groups = []
            lastErrorMessage = L10n.format("errors.groupLoadFailed", error.localizedDescription)
            return .failed
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            groups = []
            return .notFound
        }

        do {
            let data = try Data(contentsOf: fileURL)
            groups = try JSONDecoder().decode([AppGroup].self, from: data)
            return .loaded
        } catch let loadError {
            groups = []
            do {
                let backupURL = try backUpUnreadableGroupsFile(at: fileURL)
                lastErrorMessage = L10n.format(
                    "errors.groupLoadFailedBackedUp",
                    loadError.localizedDescription,
                    backupURL.lastPathComponent
                )
            } catch {
                isSavingBlockedByUnreadableGroupsFile = true
                lastErrorMessage = L10n.format("errors.groupLoadFailed", loadError.localizedDescription)
            }
            return .failed
        }
    }

    private func backUpUnreadableGroupsFile(at fileURL: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let directoryURL = fileURL.deletingLastPathComponent()
        let baseName = "\(fileURL.lastPathComponent).corrupt-\(formatter.string(from: Date()))"
        var backupURL = directoryURL.appendingPathComponent(baseName)
        if FileManager.default.fileExists(atPath: backupURL.path) {
            backupURL = directoryURL.appendingPathComponent("\(baseName)-\(UUID().uuidString)")
        }
        try FileManager.default.moveItem(at: fileURL, to: backupURL)
        return backupURL
    }

    private func save() {
        guard !isSavingBlockedByUnreadableGroupsFile else {
            lastErrorMessage = L10n.string("errors.groupSaveBlockedByUnreadableFile")
            return
        }

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
            lastErrorMessage = L10n.format("errors.groupSaveFailed", error.localizedDescription)
        }
    }

    private func regenerateMissingOrDeletedIcons() {
        var didChange = false
        for index in groups.indices {
            let iconFileName = groups[index].iconFileName
            let iconExists = iconFileName.flatMap { iconService.iconURL(for: $0) }
                .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            guard iconFileName == nil || iconExists == false else { continue }
            do {
                groups[index].iconFileName = try iconService.generateIcon(for: groups[index])
                didChange = true
            } catch {
                lastErrorMessage = L10n.format("errors.groupIconCreationFailed", error.localizedDescription)
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
            cleanupOrphanedIcons()
        } catch {
            lastErrorMessage = L10n.format("errors.groupIconRefreshFailed", error.localizedDescription)
            // The app-list change must still be persisted; a save failure message overrides the icon one.
            save()
        }
    }

    private func regenerateStaleLaunchers() {
        for group in groups {
            do {
                _ = try launcherGeneratorService.regenerateLauncherIfStale(for: group)
            } catch {
                lastErrorMessage = L10n.format("errors.launcherGenerationFailed", error.localizedDescription)
            }
        }
    }

    private func deleteResources(for group: AppGroup) {
        deleteIcon(for: group)
        do {
            try launcherGeneratorService.deleteLauncher(for: group)
        } catch {
            lastErrorMessage = L10n.format("errors.launcherDeletionFailed", error.localizedDescription)
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

    private func cleanupOrphanedIcons() {
        let referencedFileNames = Set(groups.compactMap(\.iconFileName))

        do {
            try iconCleanupService.cleanup(referencedFileNames: referencedFileNames)
        } catch {
            // Cleanup should not block the main group management flows.
        }
    }

    private func updateAccessibilityPermissionWarning(for results: [ActivationResult]) {
        let isPermissionMissing = results.contains { result in
            if case .accessibilityPermissionMissing = result { true } else { false }
        }
        if isPermissionMissing {
            needsAccessibilityPermission = true
        } else if results.contains(where: \.isSuccess) {
            needsAccessibilityPermission = false
        }
    }

    private static func frontmostActivationOrder(for group: AppGroup) -> [GroupedApp] {
        // Later macOS activation requests are brought farther forward, so request back-to-front.
        Array(group.apps.reversed())
    }
}
