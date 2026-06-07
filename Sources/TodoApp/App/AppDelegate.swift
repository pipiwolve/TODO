import AppKit
import Carbon
import SwiftUI
import TodoCore

@MainActor
protocol AppActions: AnyObject {
    func showSticky()
    func showCapture(model: AppModel)
    func showTimeline(model: AppModel)
    func showSettings()
    func showAddProject(model: AppModel)
    func showArchivedProjects(model: AppModel)
    func setStickyPinned(_ pinned: Bool)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, AppActions {
    weak var stickyWindow: NSWindow?
    var openStickyWindow: (() -> Void)?

    private var stickyHotkey: GlobalHotkey?
    private var captureHotkey: GlobalHotkey?
    private var captureController: NSWindowController?
    private var timelineController: NSWindowController?
    private var settingsController: NSWindowController?
    private var addProjectController: NSWindowController?
    private var archivedProjectsController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        stickyHotkey = GlobalHotkey(keyCode: UInt32(kVK_ANSI_G), modifiers: .commandModifier | .optionModifier, id: 1) { [weak self] in
            Task { @MainActor in
                self?.showSticky()
            }
        }
        captureHotkey = GlobalHotkey(keyCode: UInt32(kVK_ANSI_S), modifiers: .commandModifier | .optionModifier, id: 2) { [weak self] in
            Task { @MainActor in
                guard let self, let model = AppModel.shared else { return }
                self.showCapture(model: model)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSticky()
        return true
    }

    func showSticky() {
        if let stickyWindow {
            stickyWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            openStickyWindow?()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func showCapture(model: AppModel) {
        if let window = captureController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = CaptureView(model: model) { [weak self] in
            self?.captureController?.close()
            self?.captureController = nil
        }
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Quick Capture"
        window.contentView = NSHostingView(rootView: view)
        window.isFloatingPanel = true
        window.level = .floating
        window.titlebarAppearsTransparent = true
        window.center()
        let controller = NSWindowController(window: window)
        captureController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showTimeline(model: AppModel) {
        if let window = timelineController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Timeline"
        window.contentView = NSHostingView(rootView: TimelineView(model: model))
        window.center()
        let controller = NSWindowController(window: window)
        timelineController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        guard let model = AppModel.shared else { return }
        if let window = settingsController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 230),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.isFloatingPanel = true
        window.level = .floating
        window.titlebarAppearsTransparent = true
        window.center()
        let controller = NSWindowController(window: window)
        settingsController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showAddProject(model: AppModel) {
        if let window = addProjectController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 150),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Add Project"
        window.contentView = NSHostingView(rootView: AddProjectPanel(model: model))
        window.isFloatingPanel = true
        window.level = .floating
        window.titlebarAppearsTransparent = true
        window.center()
        let controller = NSWindowController(window: window)
        addProjectController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showArchivedProjects(model: AppModel) {
        if let window = archivedProjectsController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Archived Projects"
        window.contentView = NSHostingView(rootView: ArchivedProjectsPanel(model: model))
        window.center()
        let controller = NSWindowController(window: window)
        archivedProjectsController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setStickyPinned(_ pinned: Bool) {
        stickyWindow?.level = pinned ? .floating : .normal
    }
}
