import Foundation

final class LauncherActivationController {
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
