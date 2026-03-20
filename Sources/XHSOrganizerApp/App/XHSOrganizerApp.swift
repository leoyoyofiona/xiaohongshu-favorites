import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var windowObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        windowObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeMainNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                Task { @MainActor in
                    self?.configure(window: window)
                }
            }
        )

        windowObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                Task { @MainActor in
                    self?.configure(window: window)
                }
            }
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let window = NSApp.windows.first {
                self.configure(window: window)
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }

    private func configure(window: NSWindow) {
        window.styleMask.insert(.resizable)
        window.delegate = self
        window.aspectRatio = .zero
        window.contentAspectRatio = .zero
        window.minSize = NSSize(width: 980, height: 620)
        window.contentMinSize = NSSize(width: 980, height: 620)
        window.maxSize = NSSize(width: 10000, height: 10000)
        window.contentMaxSize = NSSize(width: 10000, height: 10000)
        window.resizeIncrements = NSSize(width: 1, height: 1)
        window.contentResizeIncrements = NSSize(width: 1, height: 1)
    }
}

@main
struct XHSOrganizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("小红书收藏导航") {
            ContentView()
        }
        .defaultSize(width: 1380, height: 860)
    }
}
