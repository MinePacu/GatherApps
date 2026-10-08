import AppKit
import XCTest
@testable import GatherApps

@MainActor
final class GroupIconPerformanceTests: XCTestCase {
    func testIconURLDoesNotCreateIconsDirectory() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsGroupIconURL-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let url = GroupIconService(iconsDirectoryURL: directory).iconURL(for: "a.png")

        XCTAssertEqual(url, directory.appendingPathComponent("a.png"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testRenderedIconDoesNotDependOnCurrentAppearance() throws {
        let service = GroupIconService(
            iconsDirectoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("GatherAppsIconAppearance-\(UUID().uuidString)", isDirectory: true)
        )
        let group = AppGroup(name: "Appearance")

        func renderedTIFF(appearanceName: NSAppearance.Name) throws -> Data? {
            var data: Data?
            var renderError: Error?
            try XCTUnwrap(NSAppearance(named: appearanceName)).performAsCurrentDrawingAppearance {
                do {
                    data = try service.iconImage(for: group).tiffRepresentation
                } catch {
                    renderError = error
                }
            }
            if let renderError { throw renderError }
            return data
        }

        let light = try XCTUnwrap(renderedTIFF(appearanceName: .aqua))
        let dark = try XCTUnwrap(renderedTIFF(appearanceName: .darkAqua))
        XCTAssertEqual(light, dark)
    }

    func testIconsDirectoryLocationMatchesIconsDirectory() throws {
        XCTAssertEqual(
            AppSupportPaths.iconsDirectoryLocation?.standardizedFileURL.path,
            try AppSupportPaths.iconsDirectory.standardizedFileURL.path
        )
    }

    func testIconImageCacheDecodesFileOnce() throws {
        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("\(UUID().uuidString).png")
        try writePNG(to: url)

        let first = try XCTUnwrap(GroupIconImageCache.image(for: url))
        try FileManager.default.removeItem(at: url)
        let second = try XCTUnwrap(GroupIconImageCache.image(for: url))

        XCTAssertTrue(first === second)
    }

    func testIconImageCacheDoesNotCacheMissingFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("\(UUID().uuidString).png")

        XCTAssertNil(GroupIconImageCache.image(for: url))

        try writePNG(to: url)

        XCTAssertNotNil(GroupIconImageCache.image(for: url))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatherAppsGroupIconCache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writePNG(to url: URL) throws {
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 4,
                pixelsHigh: 4,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        try pngData.write(to: url)
    }
}
