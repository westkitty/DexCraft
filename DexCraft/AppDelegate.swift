import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let collapsedSize = NSSize(width: 450, height: 640)
    private let expandedSize = NSSize(width: 900, height: 640)

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private lazy var viewModel: PromptEngineViewModel = {
        let vm = PromptEngineViewModel()
        vm.onRevealStateChanged = { [weak self] expanded in
            self?.resizePopover(expanded: expanded, animated: true)
        }
        return vm
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPopover()
        setupStatusItem()
        setupKeyboardShortcut()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = collapsedSize

        let rootView = RootPopoverView(viewModel: viewModel)
            .preferredColorScheme(.dark)
        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }
        button.title = "DexCraft"
        if let hammer = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: "DexCraft") {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            button.image = hammer.withSymbolConfiguration(symbolConfig)
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
        } else {
            button.image = nil
        }
        button.action = #selector(togglePopover(_:))
        button.target = self
    }

    private func setupKeyboardShortcut() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isToggleShortcut(event) else { return }
            DispatchQueue.main.async {
                self.togglePopover(nil)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.isToggleShortcut(event) {
                self.togglePopover(nil)
                return nil
            }
            return event
        }
    }

    private func isToggleShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let required: NSEvent.ModifierFlags = [.command, .shift]
        let disallowed: NSEvent.ModifierFlags = [.control, .option]

        return event.keyCode == 49 && flags.isSuperset(of: required) && flags.intersection(disallowed).isEmpty
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            resizePopover(expanded: viewModel.isResultPanelVisible, animated: false)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func resizePopover(expanded: Bool, animated: Bool) {
        let targetSize = expanded ? expandedSize : collapsedSize

        guard popover.isShown,
              let window = popover.contentViewController?.view.window
        else {
            popover.contentSize = targetSize
            return
        }

        var frame = window.frame
        let deltaWidth = targetSize.width - frame.width
        frame.origin.x -= deltaWidth
        frame.size = targetSize

        popover.contentSize = targetSize

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }
}
