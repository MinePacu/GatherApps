import Foundation

enum GatherTabURLScheme {
    static let scheme = "gathertab"
    static let activateGroupHost = "activate-group"

    static func activationURL(for groupID: UUID, showsGatherTabWindow: Bool = true) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = activateGroupHost
        components.path = "/\(groupID.uuidString)"
        if !showsGatherTabWindow {
            components.queryItems = [
                URLQueryItem(name: "showWindow", value: "false")
            ]
        }
        return components.url!
    }

    static func groupID(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == activateGroupHost else {
            return nil
        }

        let idString = url.pathComponents.dropFirst().first
        return idString.flatMap(UUID.init(uuidString:))
    }

    static func showsGatherTabWindow(from url: URL) -> Bool {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let value = components.queryItems?.first(where: { $0.name == "showWindow" })?.value
        else {
            return true
        }

        return value.lowercased() != "false"
    }
}
