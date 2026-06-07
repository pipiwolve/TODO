import AppKit

enum WindowStyler {
    @MainActor
    static func configureSticky(_ window: NSWindow) {
        window.title = "Todo Sticky"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.setContentSize(NSSize(width: 340, height: 430))

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.maxX - window.frame.width - 18,
                y: visible.maxY - window.frame.height - 18
            )
            window.setFrameOrigin(origin)
        }
    }
}
