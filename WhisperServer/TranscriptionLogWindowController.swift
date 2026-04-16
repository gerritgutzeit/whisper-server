import AppKit
import SwiftUI

/// Hosts `TranscriptionLogView` in a standard resizable window.
final class TranscriptionLogWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: TranscriptionLogView())
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "Transcription log"
            w.minSize = NSSize(width: 560, height: 400)
            w.contentViewController = hosting
            w.center()
            w.setFrameAutosaveName("TranscriptionLogWindow")
            w.isReleasedWhenClosed = false
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
