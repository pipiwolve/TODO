import AppKit
import SwiftUI
import TodoCore

@main
struct TodoStickyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.bootstrap()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Todo Sticky", id: WindowID.sticky.rawValue) {
            StickyNoteView(model: model)
                .frame(width: 340, height: 430)
                .onAppear {
                    model.actions = appDelegate
                    appDelegate.openStickyWindow = {
                        openWindow(id: WindowID.sticky.rawValue)
                    }
                }
                .background(WindowAccessor { window in
                    WindowStyler.configureSticky(window)
                    appDelegate.stickyWindow = window
                    model.isPinned = window.level == .floating
                })
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Quick Capture") {
                    appDelegate.showCapture(model: model)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Show Timeline") {
                    appDelegate.showTimeline(model: model)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 420)
        }

        MenuBarExtra("轻话", systemImage: "text.bubble") {
            Button("Wake Sticky") {
                appDelegate.showSticky()
            }
            .keyboardShortcut("g", modifiers: [.command, .option])
            Button("Quick Capture") {
                appDelegate.showCapture(model: model)
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            Divider()
            Button("Timeline") {
                appDelegate.showTimeline(model: model)
            }
            Button("Settings") {
                appDelegate.showSettings()
            }
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }
}

enum WindowID: String {
    case sticky
}
