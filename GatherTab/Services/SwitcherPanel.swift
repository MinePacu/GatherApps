import AppKit

final class SwitcherPanel: NSPanel {
    enum KeyCommand {
        case moveUp
        case moveDown
        case activate
        case dismiss
    }

    var keyCommandHandler: ((KeyCommand) -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126:
            keyCommandHandler?(.moveUp)
        case 125:
            keyCommandHandler?(.moveDown)
        case 36:
            keyCommandHandler?(.activate)
        case 53:
            keyCommandHandler?(.dismiss)
        default:
            super.keyDown(with: event)
        }
    }
}
