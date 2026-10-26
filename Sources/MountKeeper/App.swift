import AppKit

@main
@MainActor
enum MountKeeperApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // No Dock icon or menu bar item while running in the background;
        // AppDelegate switches to .regular while the window is open.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
