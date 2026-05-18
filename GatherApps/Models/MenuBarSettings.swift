import Combine
import Foundation

@MainActor
final class MenuBarSettings: ObservableObject {
    @Published var showsStatusBarItem: Bool {
        didSet { defaults.set(showsStatusBarItem, forKey: Keys.showsStatusBarItem) }
    }

    @Published var launchesAtLogin: Bool {
        didSet { defaults.set(launchesAtLogin, forKey: Keys.launchesAtLogin) }
    }

    @Published var showsDockIcon: Bool {
        didSet { defaults.set(showsDockIcon, forKey: Keys.showsDockIcon) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsStatusBarItem = defaults.object(forKey: Keys.showsStatusBarItem) as? Bool ?? true
        launchesAtLogin = defaults.object(forKey: Keys.launchesAtLogin) as? Bool ?? false
        showsDockIcon = defaults.object(forKey: Keys.showsDockIcon) as? Bool ?? true
    }

    private enum Keys {
        static let showsStatusBarItem = "menuBar.showsStatusBarItem"
        static let launchesAtLogin = "menuBar.launchesAtLogin"
        static let showsDockIcon = "menuBar.showsDockIcon"
    }
}
