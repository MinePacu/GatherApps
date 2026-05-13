import AppKit
import Foundation

struct LauncherAppGeneratorService {
    private static let launcherExecutableName = "GatherTabLauncher"

    private let iconService = GroupIconService()
    private let launcherRuntimeExecutableURL: URL?

    init(launcherRuntimeExecutableURL: URL? = LauncherRuntimeLocator.defaultRuntimeExecutableURL()) {
        self.launcherRuntimeExecutableURL = launcherRuntimeExecutableURL
    }

    func generateLauncher(for group: AppGroup, destinationDirectory: URL? = nil) throws -> LauncherGenerationResult {
        let baseDirectory = try destinationDirectory ?? defaultDestinationDirectory()
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let displayName = launcherDisplayName(for: group)
        let appURL = baseDirectory.appendingPathComponent("\(displayName).app", isDirectory: true)

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

        try writeExecutable(
            to: macOSURL.appendingPathComponent(executableName),
            groupID: group.id
        )
        try writeInfoPlist(
            to: contentsURL.appendingPathComponent("Info.plist"),
            displayName: displayName,
            executableName: executableName,
            iconFileBaseName: iconFileBaseName,
            bundleIdentifier: bundleIdentifier,
            groupID: group.id
        )
        try writeIcon(
            for: group,
            to: resourcesURL.appendingPathComponent("\(iconFileBaseName).icns")
        )

        return LauncherGenerationResult(appURL: appURL, bundleIdentifier: bundleIdentifier)
    }

    func defaultDestinationDirectory() throws -> URL {
        try AppSupportPaths.userLaunchersDirectory
    }

    private func launcherDisplayName(for group: AppGroup) -> String {
        "GatherTab - \(sanitizedFileName(group.name))"
    }

    private func bundleIdentifier(for group: AppGroup) -> String {
        "com.minepacu.GatherTab.launcher.\(group.id.uuidString.lowercased())"
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

        try FileManager.default.copyItem(at: launcherRuntimeExecutableURL, to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func writeInfoPlist(
        to url: URL,
        displayName: String,
        executableName: String,
        iconFileBaseName: String,
        bundleIdentifier: String,
        groupID: UUID
    ) throws {
        let info: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": executableName,
            "CFBundleIconFile": iconFileBaseName,
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": displayName,
            "CFBundleDisplayName": displayName,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "GatherTabGroupID": groupID.uuidString,
            "GatherTabShowsGatherTabWindow": false,
            "LSMinimumSystemVersion": "14.0"
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    private func writeIcon(for group: AppGroup, to outputURL: URL) throws {
        let pngURL = try pngIconURL(for: group)
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

        guard let sourceImage = NSImage(contentsOf: pngURL) else {
            throw CocoaError(.fileReadCorruptFile)
        }

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

    private func pngIconURL(for group: AppGroup) throws -> URL {
        if
            let iconFileName = group.iconFileName,
            let iconURL = iconService.iconURL(for: iconFileName),
            FileManager.default.fileExists(atPath: iconURL.path)
        {
            return iconURL
        }

        let iconFileName = try iconService.generateIcon(for: group)
        guard let iconURL = iconService.iconURL(for: iconFileName) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return iconURL
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

private enum LauncherRuntimeLocator {
    static func defaultRuntimeExecutableURL(bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?
            .appendingPathComponent("LauncherRuntime", isDirectory: true)
            .appendingPathComponent("GatherTabLauncherRuntime")
    }
}
