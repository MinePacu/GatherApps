import Foundation

enum GatherTabURLScheme {
    static let scheme = "gathertab"
    static let activateGroupHost = "activate-group"

    static func activationURL(for groupID: UUID) -> URL {
        URL(string: "\(scheme)://\(activateGroupHost)/\(groupID.uuidString)")!
    }

    static func groupID(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == activateGroupHost else {
            return nil
        }

        let idString = url.pathComponents.dropFirst().first
        return idString.flatMap(UUID.init(uuidString:))
    }
}
