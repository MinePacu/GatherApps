import Foundation

struct UpdateMetadata: Equatable {
    let shortVersion: String
    let buildVersion: String?
    let releaseNotesHTML: String?
}

struct UpdateVersion: Equatable {
    private let components: [Int]

    init(_ rawValue: String) {
        components = rawValue
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }

    func isNewer(than other: UpdateVersion) -> Bool {
        let componentCount = max(components.count, other.components.count)

        for index in 0..<componentCount {
            let lhs = components[safe: index] ?? 0
            let rhs = other.components[safe: index] ?? 0

            if lhs != rhs {
                return lhs > rhs
            }
        }

        return false
    }
}

enum UpdateMetadataParserError: Error {
    case missingItem
    case missingShortVersion
}

struct UpdateMetadataParser {
    func parse(data: Data) throws -> UpdateMetadata {
        let document = try XMLDocument(data: data, options: [.nodePreserveCDATA])
        let item = try document.nodes(forXPath: "/rss/channel/item").first

        guard let item else {
            throw UpdateMetadataParserError.missingItem
        }

        guard let shortVersion = try item.firstString(forXPath: "sparkle:shortVersionString") else {
            throw UpdateMetadataParserError.missingShortVersion
        }

        return UpdateMetadata(
            shortVersion: shortVersion,
            buildVersion: try item.firstString(forXPath: "sparkle:version"),
            releaseNotesHTML: try item.firstString(forXPath: "description")
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension XMLNode {
    func firstString(forXPath xpath: String) throws -> String? {
        try nodes(forXPath: xpath).first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
