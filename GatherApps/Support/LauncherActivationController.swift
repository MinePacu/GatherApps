import Foundation

final class LauncherActivationController {
    static let backgroundRelaunchArgument = "--gatherapps-background-relaunch"

    private let minimumActivationInterval: TimeInterval
    private let now: () -> Date
    private let dispatchActivation: () -> Void
    private let hideLauncher: () -> Void
    private var lastActivationDate = Date.distantPast

    init(
        minimumActivationInterval: TimeInterval = 0.5,
        now: @escaping () -> Date = Date.init,
        dispatchActivation: @escaping () -> Void,
        hideLauncher: @escaping () -> Void
    ) {
        self.minimumActivationInterval = minimumActivationInterval
        self.now = now
        self.dispatchActivation = dispatchActivation
        self.hideLauncher = hideLauncher
    }

    func handleLaunch(arguments: [String]) {
        guard arguments.contains(Self.backgroundRelaunchArgument) else {
            handleActivation()
            return
        }

        // GatherApps relaunched this launcher after regenerating it; the user did not
        // ask to activate the group. Treat the launch as the latest activation so an
        // immediate didBecomeActive is debounced as well.
        lastActivationDate = now()
        hideLauncher()
    }

    func handleActivation() {
        defer { hideLauncher() }

        let activationDate = now()
        guard activationDate.timeIntervalSince(lastActivationDate) > minimumActivationInterval else {
            return
        }

        lastActivationDate = activationDate
        dispatchActivation()
    }
}
