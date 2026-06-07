import AppKit
import SwiftUI

struct GroupDetailView: View {
    @ObservedObject var store: AppGroupStore
    let groupID: AppGroup.ID

    @State private var runningApps: [RunningAppInfo] = []
    private let runningAppService = RunningAppService()

    var body: some View {
        if let group = store.groups.first(where: { $0.id == groupID }) {
            VStack(spacing: 0) {
                header(for: group)

                Divider()

                HSplitView {
                    groupedAppsList(for: group)
                        .frame(minWidth: 280)

                    runningAppsList(for: group)
                        .frame(minWidth: 320)
                }
            }
            .onAppear(perform: refreshRunningApps)
        } else {
            ContentUnavailableView("groupDetail.groupNotFound", systemImage: "exclamationmark.triangle")
        }
    }

    private func header(for group: AppGroup) -> some View {
        HStack(spacing: 16) {
            GroupIconView(iconURL: store.iconImageURL(for: group), size: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(L10n.format("common.appCount", group.apps.count))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.activate(groupID: group.id)
            } label: {
                Label("groupDetail.activateGroup", systemImage: "play.fill")
            }
            .controlSize(.large)
            .disabled(group.apps.isEmpty)

            VStack(alignment: .trailing, spacing: 8) {
                Toggle(isOn: launcherWindowPolicyBinding(for: group)) {
                    Text("groupDetail.launcherShowsGatherAppsWindow")
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Button {
                    store.generateLauncher(
                        for: group.id,
                        showsGatherAppsWindow: group.launcherShowsGatherAppsWindow
                    )
                } label: {
                    Label("groupDetail.generateLauncher", systemImage: "app.badge")
                }
                .controlSize(.large)
            }
        }
        .padding(20)
    }

    private func groupedAppsList(for group: AppGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("groupDetail.groupApps")

            if group.apps.isEmpty {
                ContentUnavailableView("groupDetail.noApps", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(group.apps) { app in
                        HStack(spacing: 10) {
                            AppIconImage(image: icon(for: app), size: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .lineLimit(1)
                                Text(detailText(for: app))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                if let index = group.apps.firstIndex(where: { $0.id == app.id }) {
                                    store.removeApps(at: IndexSet(integer: index), from: group.id)
                                }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help(Text("groupDetail.removeFromGroup"))
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        store.removeApps(at: offsets, from: group.id)
                    }
                }
            }

            activationMessages
            launcherMessage
        }
    }

    private func runningAppsList(for group: AppGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionTitle("groupDetail.runningApps")
                Spacer()
                Button {
                    refreshRunningApps()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(Text("groupDetail.refreshList"))
                .padding(.trailing, 12)
            }

            List(availableRunningApps(for: group)) { app in
                HStack(spacing: 10) {
                    AppIconImage(image: runningAppService.icon(for: app), size: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                            .lineLimit(1)
                        Text(detailText(for: app))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        store.add(app, to: group.id)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(Text("groupDetail.addToGroup"))
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var activationMessages: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(store.lastActivationResults.enumerated()), id: \.offset) { _, result in
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(result.isSuccess ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .padding([.horizontal, .bottom], 12)
    }

    private var launcherMessage: some View {
        Group {
            if let result = store.lastLauncherGenerationResult {
                HStack(spacing: 8) {
                    Text(L10n.format("groupDetail.launcherCreated", result.appURL.path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer()

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([result.appURL])
                    } label: {
                        Label("groupDetail.revealInFinder", systemImage: "magnifyingglass")
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding([.horizontal, .bottom], 12)
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .padding([.top, .horizontal], 12)
            .padding(.bottom, 8)
    }

    private func refreshRunningApps() {
        runningApps = runningAppService.fetchRunningApps()
    }

    private func launcherWindowPolicyBinding(for group: AppGroup) -> Binding<Bool> {
        Binding(
            get: { group.launcherShowsGatherAppsWindow },
            set: { store.setLauncherShowsGatherAppsWindow($0, for: group.id) }
        )
    }

    private func availableRunningApps(for group: AppGroup) -> [RunningAppInfo] {
        runningApps.filter { runningApp in
            !group.apps.contains(where: { $0.id == runningApp.id })
        }
    }

    private func icon(for app: GroupedApp) -> NSImage? {
        if app.kind == .executable, let executablePath = app.executablePath {
            return NSWorkspace.shared.icon(forFile: executablePath)
        }

        if let appPath = app.appPath, FileManager.default.fileExists(atPath: appPath) {
            return NSWorkspace.shared.icon(forFile: appPath)
        }

        guard
            let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == app.bundleIdentifier
            }),
            let bundleURL = runningApp.bundleURL
        else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: bundleURL.path)
    }

    private func detailText(for app: GroupedApp) -> String {
        switch app.kind {
        case .bundle:
            app.bundleIdentifier
        case .executable:
            app.executablePath ?? app.bundleIdentifier
        }
    }

    private func detailText(for app: RunningAppInfo) -> String {
        switch app.kind {
        case .bundle:
            app.bundleIdentifier
        case .executable:
            app.executableURL?.path ?? app.bundleIdentifier
        }
    }
}
