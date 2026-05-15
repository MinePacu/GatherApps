import AppKit
import Foundation

@MainActor
struct GroupIconService {
    private let iconSize = NSSize(width: 128, height: 128)
    private let tileSize = NSSize(width: 54, height: 54)

    func iconURL(for fileName: String) -> URL? {
        try? AppSupportPaths.iconsDirectory.appendingPathComponent(fileName)
    }

    func generateIcon(for group: AppGroup) throws -> String {
        let fileName = "\(group.id.uuidString)-\(UUID().uuidString).png"
        let outputURL = try AppSupportPaths.iconsDirectory.appendingPathComponent(fileName)
        let image = makeIcon(for: group)

        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        try pngData.write(to: outputURL, options: .atomic)
        return fileName
    }

    private func makeIcon(for group: AppGroup) -> NSImage {
        let image = NSImage(size: iconSize)
        image.lockFocus()

        drawBackground()

        let icons = group.apps.prefix(4).compactMap(iconForGroupedApp)
        if icons.isEmpty {
            drawPlaceholderGlyph()
        } else {
            drawAppIcons(icons)
        }

        image.unlockFocus()
        return image
    }

    private func iconForGroupedApp(_ app: GroupedApp) -> NSImage? {
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

    private func drawBackground() {
        let rect = NSRect(origin: .zero, size: iconSize)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24).fill()

        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 23, yRadius: 23)
        border.lineWidth = 2
        border.stroke()
    }

    private func drawAppIcons(_ icons: [NSImage]) {
        let positions = [
            NSPoint(x: 18, y: 64),
            NSPoint(x: 56, y: 64),
            NSPoint(x: 18, y: 26),
            NSPoint(x: 56, y: 26)
        ]

        for (index, icon) in icons.enumerated() {
            let rect = NSRect(origin: positions[index], size: tileSize)
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    private func drawPlaceholderGlyph() {
        let symbol = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Empty group")
        symbol?.withSymbolConfiguration(.init(pointSize: 54, weight: .regular))?
            .draw(in: NSRect(x: 37, y: 37, width: 54, height: 54), from: .zero, operation: .sourceOver, fraction: 0.65)
    }
}
