import AppKit
import SwiftUI

@MainActor
final class SwitcherWindowController: NSObject, NSWindowDelegate {
    private var panel: SwitcherPanel?
    private var viewModel: SwitcherViewModel?

    func showSwitcher(store: AppGroupStore) {
        if let panel, panel.isVisible {
            viewModel?.refresh()
            center(panel)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let viewModel = SwitcherViewModel(store: store)
        viewModel.onDismiss = { [weak self] in
            self?.closeSwitcher()
        }

        let contentView = FloatingSwitcherView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: contentView)
        let panel = SwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = "GatherApps Switcher"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .transient]
        panel.contentViewController = hostingController
        panel.delegate = self
        panel.keyCommandHandler = { [weak viewModel] command in
            switch command {
            case .moveUp:
                viewModel?.moveSelectionUp()
            case .moveDown:
                viewModel?.moveSelectionDown()
            case .activate:
                viewModel?.activateSelectedGroup()
            case .dismiss:
                viewModel?.dismiss()
            }
        }

        self.viewModel = viewModel
        self.panel = panel

        center(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeSwitcher() {
        panel?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        viewModel?.refresh()
    }

    private func center(_ panel: NSPanel) {
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let panelFrame = panel.frame
            let origin = NSPoint(
                x: visibleFrame.midX - panelFrame.width / 2,
                y: visibleFrame.midY - panelFrame.height / 2
            )
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }
    }
}
