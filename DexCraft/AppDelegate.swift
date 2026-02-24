import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let collapsedSize = NSSize(width: 450, height: 640)
    private let expandedSize = NSSize(width: 900, height: 640)

    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var toggleDrawerMenuItem: NSMenuItem!
    private var popover: NSPopover!
    private var detachedWindow: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private lazy var viewModel: PromptEngineViewModel = {
        let vm = PromptEngineViewModel()
        vm.onRevealStateChanged = { [weak self] expanded in
            self?.resizePopover(expanded: expanded, animated: true)
            self?.updateDetachedWindowMinimumSize(expanded: expanded)
        }
        vm.onDetachedWindowToggleRequested = { [weak self] in
            self?.toggleDetachedWindow()
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
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.action = #selector(handleStatusItemClick(_:))
        button.target = self

        setupStatusMenu()
    }

    private func setupStatusMenu() {
        let menu = NSMenu()

        toggleDrawerMenuItem = NSMenuItem(title: "Open Drawer", action: #selector(togglePopover(_:)), keyEquivalent: "")
        toggleDrawerMenuItem.target = self
        menu.addItem(toggleDrawerMenuItem)

        let batchExportItem = NSMenuItem(title: "Run Batch Export", action: #selector(runBatchExport(_:)), keyEquivalent: "")
        batchExportItem.target = self
        menu.addItem(batchExportItem)

        let quitItem = NSMenuItem(title: "Quit DexCraft", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusMenu = menu
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }

        if event.type == .rightMouseUp {
            toggleDrawerMenuItem.title = popover.isShown ? "Close Drawer" : "Open Drawer"
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover(sender)
        }
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    @objc private func runBatchExport(_ sender: Any?) {
        do {
            let baseDir = BatchExportService.appSupportDirURL()
            try BatchExportService.ensureDirExists(baseDir)

            let inputURL = BatchExportService.inputsURL()
            let outputURL = BatchExportService.outputsURL()
            let fileManager = FileManager.default

            if !fileManager.fileExists(atPath: inputURL.path) {
                try BatchExportService.writeBatchInputsTemplate(to: inputURL)
                showRevealAlert(
                    title: "Created batch inputs template",
                    message: "Template created at:\n\(inputURL.path)",
                    revealURL: baseDir
                )
                return
            }

            let summary = try BatchExportService.runBatchExport(inputsURL: inputURL, outputsURL: outputURL)
            showRevealAlert(
                title: "Batch export complete",
                message: "Processed: \(summary.processedCount)\nFailures: \(summary.failureCount)\nOutput: \(outputURL.path)",
                revealURL: baseDir
            )
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Batch export failed."
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func showRevealAlert(title: String, message: String, revealURL: URL) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Reveal in Finder")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([revealURL])
        }
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
        if viewModel.isDetachedWindowActive {
            detachedWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

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

    private func toggleDetachedWindow() {
        if detachedWindow == nil {
            openDetachedWindow()
        } else {
            closeDetachedWindow(showPopoverAfterClose: true)
        }
    }

    private func openDetachedWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }

        let minWidth = viewModel.isResultPanelVisible ? 760 : collapsedSize.width
        let width = max(viewModel.isResultPanelVisible ? expandedSize.width : collapsedSize.width, minWidth)
        let rect = NSRect(x: 0, y: 0, width: width, height: collapsedSize.height)
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.title = "DexCraft"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        panel.minSize = NSSize(width: minWidth, height: 520)
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(
            rootView: RootPopoverView(viewModel: viewModel).preferredColorScheme(.dark)
        )
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        detachedWindow = panel
        viewModel.setDetachedWindowActive(true)
    }

    private func closeDetachedWindow(showPopoverAfterClose: Bool) {
        guard let window = detachedWindow else { return }
        window.close()

        if showPopoverAfterClose, let button = statusItem.button {
            resizePopover(expanded: viewModel.isResultPanelVisible, animated: false)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow == detachedWindow
        else {
            return
        }

        detachedWindow = nil
        viewModel.setDetachedWindowActive(false)
    }

    private func updateDetachedWindowMinimumSize(expanded: Bool) {
        guard let window = detachedWindow else { return }
        let minWidth = expanded ? 760 : collapsedSize.width
        window.minSize = NSSize(width: minWidth, height: 520)
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
