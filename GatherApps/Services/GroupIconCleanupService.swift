import Foundation

@MainActor
struct GroupIconCleanupService {
    private let iconsDirectoryURL: URL?

    init(iconsDirectoryURL: URL? = nil) {
        self.iconsDirectoryURL = iconsDirectoryURL
    }

    func cleanup(referencedFileNames: Set<String>) throws {
        let directoryURL = try iconsDirectory()
        let fileManager = FileManager.default
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for fileURL in fileURLs {
            guard
                fileURL.pathExtension.lowercased() == "png",
                referencedFileNames.contains(fileURL.lastPathComponent) == false
            else {
                continue
            }

            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            try fileManager.removeItem(at: fileURL)
        }
    }

    private func iconsDirectory() throws -> URL {
        if let iconsDirectoryURL {
            try FileManager.default.createDirectory(at: iconsDirectoryURL, withIntermediateDirectories: true)
            return iconsDirectoryURL
        }

        return try AppSupportPaths.iconsDirectory
    }
}
