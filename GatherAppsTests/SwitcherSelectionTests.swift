import CoreGraphics
import Foundation
import XCTest
@testable import GatherApps

@MainActor
final class SwitcherSelectionTests: XCTestCase {
    private var testDirectory: URL!

    override func setUpWithError() throws {
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsSwitcherSelectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: testDirectory)
    }

    func testSelectionFollowsGroupWhenEarlierGroupIsDeleted() throws {
        let (store, _) = try makeStore(groupNames: ["First", "Second", "Third"])
        let viewModel = SwitcherViewModel(store: store)
        let second = store.groups[1]
        viewModel.select(second)
        XCTAssertEqual(viewModel.selectedIndex, 1)

        store.deleteGroup(id: store.groups[0].id)

        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertTrue(viewModel.isSelected(second))
        XCTAssertEqual(viewModel.groups[viewModel.selectedIndex].id, second.id)
    }

    func testSelectionStaysOnGroupWhenGroupIsAppended() throws {
        let (store, _) = try makeStore(groupNames: ["First", "Second"])
        let viewModel = SwitcherViewModel(store: store)
        let first = store.groups[0]
        viewModel.select(first)

        store.createGroup(named: "Third")

        XCTAssertEqual(store.groups.count, 3)
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertTrue(viewModel.isSelected(first))
    }

    func testDeletingSelectedGroupSelectsGroupAtSamePosition() throws {
        let (store, _) = try makeStore(groupNames: ["First", "Second", "Third"])
        let viewModel = SwitcherViewModel(store: store)
        viewModel.select(store.groups[1])
        let third = store.groups[2]

        store.deleteGroup(id: store.groups[1].id)

        XCTAssertEqual(viewModel.selectedIndex, 1)
        XCTAssertTrue(viewModel.isSelected(third))
    }

    func testDeletingSelectedLastGroupClampsToNewLastGroup() throws {
        let (store, _) = try makeStore(groupNames: ["First", "Second", "Third"])
        let viewModel = SwitcherViewModel(store: store)
        viewModel.select(store.groups[2])
        let second = store.groups[1]

        store.deleteGroup(id: store.groups[2].id)

        XCTAssertEqual(viewModel.selectedIndex, 1)
        XCTAssertTrue(viewModel.isSelected(second))
    }

    func testDeletingAllGroupsResetsSelectionAndActivationIsNoOp() throws {
        let (store, activationService) = try makeStore(groupNames: ["First", "Second"])
        let viewModel = SwitcherViewModel(store: store)
        viewModel.select(store.groups[1])

        for group in store.groups {
            store.deleteGroup(id: group.id)
        }

        XCTAssertTrue(viewModel.groups.isEmpty)
        XCTAssertEqual(viewModel.selectedIndex, 0)

        var dismissCount = 0
        viewModel.onDismiss = { dismissCount += 1 }
        viewModel.activateSelectedGroup()

        XCTAssertEqual(dismissCount, 0)
        XCTAssertTrue(activationService.requestedApps.isEmpty)
    }

    func testMoveSelectionClampsAtEndsWithoutWrapping() throws {
        let (store, _) = try makeStore(groupNames: ["First", "Second", "Third"])
        let viewModel = SwitcherViewModel(store: store)
        XCTAssertEqual(viewModel.selectedIndex, 0)

        viewModel.moveSelectionUp()
        XCTAssertEqual(viewModel.selectedIndex, 0)

        viewModel.moveSelectionDown()
        viewModel.moveSelectionDown()
        XCTAssertEqual(viewModel.selectedIndex, 2)

        viewModel.moveSelectionDown()
        XCTAssertEqual(viewModel.selectedIndex, 2)

        viewModel.moveSelectionUp()
        XCTAssertEqual(viewModel.selectedIndex, 1)
    }

    func testExecutableAppsResolvesPathOncePerProcessForDuplicateWindows() {
        let windows: [[String: Any]] = [
            Self.window(owner: "scrcpy", pid: 1234, layer: 0),
            Self.window(owner: "scrcpy", pid: 1234, layer: 0),
            Self.window(owner: "scrcpy", pid: 1234, layer: 0),
            Self.window(owner: "Other", pid: 4321, layer: 0)
        ]
        var resolvedProcessIDs: [pid_t] = []

        let apps = RunningAppService.executableApps(
            from: windows,
            excludingProcessIDs: [],
            executablePathForProcessID: { processID in
                resolvedProcessIDs.append(processID)
                return processID == 1234 ? "/opt/homebrew/bin/scrcpy" : nil
            }
        )

        XCTAssertEqual(apps, [
            RunningAppInfo(
                executablePath: "/opt/homebrew/bin/scrcpy",
                name: "scrcpy",
                processIdentifier: 1234
            )
        ])
        XCTAssertEqual(resolvedProcessIDs, [1234, 4321])
    }

    private static func window(owner: String, pid: Int, layer: Int) -> [String: Any] {
        [
            kCGWindowOwnerName as String: owner,
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: layer)
        ]
    }

    private func makeStore(groupNames: [String]) throws -> (AppGroupStore, StubAppActivationService) {
        let groupsFileURL = testDirectory.appendingPathComponent("groups.json")
        let iconsDirectory = testDirectory.appendingPathComponent("Icons", isDirectory: true)
        let launchersDirectory = testDirectory.appendingPathComponent("Launchers", isDirectory: true)
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)

        let groups = try groupNames.map { name -> AppGroup in
            let iconFileName = "\(name).png"
            try Data(name.utf8).write(to: iconsDirectory.appendingPathComponent(iconFileName))
            return AppGroup(name: name, iconFileName: iconFileName)
        }
        try JSONEncoder().encode(groups).write(to: groupsFileURL, options: .atomic)

        let activationService = StubAppActivationService()
        let iconService = GroupIconService(iconsDirectoryURL: iconsDirectory)
        let store = AppGroupStore(
            groupsFileURL: groupsFileURL,
            iconService: iconService,
            iconCleanupService: GroupIconCleanupService(iconsDirectoryURL: iconsDirectory),
            activationService: activationService,
            launcherGeneratorService: LauncherAppGeneratorService(
                iconService: iconService,
                launcherRuntimeExecutableURL: nil,
                defaultDestinationDirectory: launchersDirectory
            )
        )
        return (store, activationService)
    }
}
