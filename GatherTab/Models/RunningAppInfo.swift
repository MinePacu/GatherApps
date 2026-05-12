import Foundation

struct RunningAppInfo: Identifiable, Equatable {
    var id: String { bundleIdentifier }

    let bundleIdentifier: String
    let name: String
    let appURL: URL
}
