import AppKit
import Foundation

protocol LauncherAppLifecycleManaging {
    func isLauncherRunning(bundleIdentifier: String) -> Bool
    func terminateLauncher(bundleIdentifier: String) -> Bool
    func forceTerminateLauncher(bundleIdentifier: String)
    func launchLauncher(at appURL: URL)
}

struct LauncherAppGeneratorService {
    private static let launcherExecutableName = "GatherAppsLauncher"
    private static let launcherSchemaVersion = 2
    private static let launcherRuntimeVersion = 2

    private let iconService: GroupIconService
    private let launcherRuntimeExecutableURL: URL?
    private let appBundleURL: URL
    private let customDefaultDestinationDirectory: URL?
    private let launcherAppLifecycleManager: LauncherAppLifecycleManaging

    init(
        iconService: GroupIconService? = nil,
        launcherRuntimeExecutableURL: URL? = LauncherRuntimeLocator.defaultRuntimeExecutableURL(),
        appBundleURL: URL = Bundle.main.bundleURL,
        defaultDestinationDirectory: URL? = nil,
        launcherAppLifecycleManager: LauncherAppLifecycleManaging = NSWorkspaceLauncherAppLifecycleManager()
    ) {
        self.iconService = iconService ?? GroupIconService()
        self.launcherRuntimeExecutableURL = launcherRuntimeExecutableURL
        self.appBundleURL = appBundleURL
        self.customDefaultDestinationDirectory = defaultDestinationDirectory
        self.launcherAppLifecycleManager = launcherAppLifecycleManager
    }

    func generateLauncher(
        for group: AppGroup,
        showsGatherAppsWindow: Bool = false,
        destinationDirectory: URL? = nil
    ) throws -> LauncherGenerationResult {
        let appURL = try launcherURL(for: group, destinationDirectory: destinationDirectory)
        try FileManager.default.createDirectory(
            at: appURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: appURL.path) {
            try FileManager.default.removeItem(at: appURL)
        }

        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let executableName = Self.launcherExecutableName
        let iconFileBaseName = "GroupIcon"
        let bundleIdentifier = bundleIdentifier(for: group)
        let displayName = launcherDisplayName(for: group)

        try writeExecutable(
            to: macOSURL.appendingPathComponent(executableName),
            groupID: group.id
        )
        let infoPlist = LauncherInfoPlist(
            displayName: displayName,
            executableName: executableName,
            iconFileBaseName: iconFileBaseName,
            bundleIdentifier: bundleIdentifier,
            groupID: group.id,
            appBundleURL: appBundleURL,
            showsGatherAppsWindow: showsGatherAppsWindow
        )
        try writeInfoPlist(
            infoPlist,
            to: contentsURL.appendingPathComponent("Info.plist")
        )
        try writeIcon(
            for: group,
            to: resourcesURL.appendingPathComponent("\(iconFileBaseName).icns")
        )

        return LauncherGenerationResult(appURL: appURL, bundleIdentifier: bundleIdentifier)
    }

    func launcherURL(for group: AppGroup, destinationDirectory: URL? = nil) throws -> URL {
        let baseDirectory = try destinationDirectory ?? defaultDestinationDirectory()
        let displayName = launcherDisplayName(for: group)
        return baseDirectory.appendingPathComponent("\(displayName).app", isDirectory: true)
    }

    func deleteLauncher(for group: AppGroup, destinationDirectory: URL? = nil) throws {
        let appURL = try launcherURL(for: group, destinationDirectory: destinationDirectory)
        guard FileManager.default.fileExists(atPath: appURL.path) else { return }
        try FileManager.default.removeItem(at: appURL)
    }

    func regenerateLauncherIfStale(
        for group: AppGroup,
        destinationDirectory: URL? = nil
    ) throws -> Bool {
        let appURL = try launcherURL(for: group, destinationDirectory: destinationDirectory)
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            return false
        }

        guard try launcherIsStale(appURL: appURL, group: group) else {
            return false
        }

        let bundleIdentifier = bundleIdentifier(for: group)
        let wasRunning = launcherAppLifecycleManager.isLauncherRunning(bundleIdentifier: bundleIdentifier)
        if wasRunning {
            let terminated = launcherAppLifecycleManager.terminateLauncher(bundleIdentifier: bundleIdentifier)
            if !terminated {
                launcherAppLifecycleManager.forceTerminateLauncher(bundleIdentifier: bundleIdentifier)
            }
        }

        _ = try generateLauncher(
            for: group,
            showsGatherAppsWindow: group.launcherShowsGatherAppsWindow,
            destinationDirectory: destinationDirectory
        )

        if wasRunning {
            launcherAppLifecycleManager.launchLauncher(at: appURL)
        }
        return true
    }

    func defaultDestinationDirectory() throws -> URL {
        try customDefaultDestinationDirectory ?? AppSupportPaths.userLaunchersDirectory
    }
}

private extension LauncherAppGeneratorService {
    private func launcherDisplayName(for group: AppGroup) -> String {
        "GatherApps - \(sanitizedFileName(group.name))"
    }

    private func bundleIdentifier(for group: AppGroup) -> String {
        "com.minepacu.GatherApps.launcher.\(group.id.uuidString.lowercased())"
    }

    private func sanitizedFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let sanitized = name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return sanitized.isEmpty ? "Untitled Group" : sanitized
    }

    private func writeExecutable(to url: URL, groupID _: UUID) throws {
        guard let launcherRuntimeExecutableURL else {
            throw CocoaError(.fileNoSuchFile)
        }

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.copyItem(at: launcherRuntimeExecutableURL, to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func writeInfoPlist(_ infoPlist: LauncherInfoPlist, to url: URL) throws {
        let info: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": infoPlist.executableName,
            "CFBundleIconFile": infoPlist.iconFileBaseName,
            "CFBundleIdentifier": infoPlist.bundleIdentifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": infoPlist.displayName,
            "CFBundleDisplayName": infoPlist.displayName,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "GatherAppsApplicationPath": infoPlist.appBundleURL.path,
            "GatherAppsGroupID": infoPlist.groupID.uuidString,
            "GatherAppsLauncherRuntimeVersion": Self.launcherRuntimeVersion,
            "GatherAppsLauncherSchemaVersion": Self.launcherSchemaVersion,
            "GatherAppsShowsGatherAppsWindow": infoPlist.showsGatherAppsWindow,
            "LSMinimumSystemVersion": "14.0"
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    private func launcherIsStale(appURL: URL, group: AppGroup) throws -> Bool {
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard
            let infoData = try? Data(contentsOf: infoPlistURL),
            let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        else {
            return true
        }

        guard info["GatherAppsLauncherSchemaVersion"] as? Int == Self.launcherSchemaVersion else {
            return true
        }
        guard info["GatherAppsLauncherRuntimeVersion"] as? Int == Self.launcherRuntimeVersion else {
            return true
        }
        guard info["GatherAppsApplicationPath"] as? String == appBundleURL.path else {
            return true
        }
        guard info["GatherAppsShowsGatherAppsWindow"] as? Bool == group.launcherShowsGatherAppsWindow else {
            return true
        }

        return try launcherRuntimeDiffers(from: appURL)
    }

    private func launcherRuntimeDiffers(from appURL: URL) throws -> Bool {
        guard let launcherRuntimeExecutableURL else {
            throw CocoaError(.fileNoSuchFile)
        }

        let generatedExecutableURL = appURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(Self.launcherExecutableName)
        guard FileManager.default.fileExists(atPath: generatedExecutableURL.path) else {
            return true
        }

        return try Data(contentsOf: generatedExecutableURL) != Data(contentsOf: launcherRuntimeExecutableURL)
    }

    private func writeIcon(for group: AppGroup, to outputURL: URL) throws {
        let iconsetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).iconset", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: iconsetURL)
        }

        try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

        let iconFiles: [(name: String, size: CGFloat)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]

        let sourceImage = try iconService.iconImage(for: group)

        for iconFile in iconFiles {
            try writePNG(
                sourceImage,
                size: NSSize(width: iconFile.size, height: iconFile.size),
                to: iconsetURL.appendingPathComponent(iconFile.name)
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func writePNG(_ image: NSImage, size: NSSize, to url: URL) throws {
        let resizedImage = NSImage(size: size)
        resizedImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        resizedImage.unlockFocus()

        guard
            let tiffData = resizedImage.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        try pngData.write(to: url, options: .atomic)
    }
}

private struct LauncherInfoPlist {
    let displayName: String
    let executableName: String
    let iconFileBaseName: String
    let bundleIdentifier: String
    let groupID: UUID
    let appBundleURL: URL
    let showsGatherAppsWindow: Bool
}

private enum LauncherRuntimeLocator {
    static func defaultRuntimeExecutableURL(bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?
            .appendingPathComponent("LauncherRuntime", isDirectory: true)
            .appendingPathComponent("GatherAppsLauncherRuntime")
    }
}

private final class NSWorkspaceLauncherAppLifecycleManager: LauncherAppLifecycleManaging {
    func isLauncherRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    func terminateLauncher(bundleIdentifier: String) -> Bool {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !applications.isEmpty else { return true }

        applications.forEach { $0.terminate() }
        return waitForTermination(of: applications, timeout: 2)
    }

    func forceTerminateLauncher(bundleIdentifier: String) {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        applications.forEach { $0.forceTerminate() }
        _ = waitForTermination(of: applications, timeout: 2)
    }

    func launchLauncher(at appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    private func waitForTermination(
        of applications: [NSRunningApplication],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while applications.contains(where: { !$0.isTerminated }) && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        return applications.allSatisfy(\.isTerminated)
    }
}
