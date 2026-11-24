import AppKit
import SafariServices

// The app that carries the extension. Opening it once is what makes Safari
// list the extension; after that its only job is to say whether the
// extension is on and to take the person to Safari's settings.
let extensionID = Bundle.main.bundleIdentifier! + ".Extension"

enum Text {
    static let title = "Reddit Enhancement Suite"
    static let explain = "Turn on Reddit Enhancement Suite in Safari\u{2019}s settings, then allow it on reddit.com. It works on old.reddit.com."
    static let on = "The extension is on."
    static let off = "The extension is off."
    static let unknown = "Safari didn\u{2019}t say whether the extension is on."
    static let translocated = "Move Reddit Enhancement Suite to your Applications folder and open it from there."
    static let openFailed = "Safari\u{2019}s settings didn\u{2019}t open. In Safari, choose Settings, then Extensions."
    static let open = "Open Safari Settings\u{2026}"
}

// Opened straight from a download, macOS runs the app from a hidden,
// read-only copy (App Translocation), and Safari cannot tie that copy to
// its extension. Moving the app with the Finder ends it.
let isTranslocated = Bundle.main.bundlePath.contains("/AppTranslocation/")

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let status = NSTextField(labelWithString: "")
    let button = NSButton(title: Text.open, target: nil, action: nil)

    func applicationDidFinishLaunching(_ note: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 210),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = Text.title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = NSTextField(labelWithString: Text.title)
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let explain = NSTextField(wrappingLabelWithString: Text.explain)
        explain.preferredMaxLayoutWidth = 320
        status.textColor = .secondaryLabelColor
        status.preferredMaxLayoutWidth = 320
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 0
        button.target = self
        button.action = #selector(openSettings)
        button.keyEquivalent = "\r"
        button.controlSize = .large
        if #available(macOS 26.0, *) { button.bezelStyle = .glass }

        let text = NSStackView(views: [title, explain, status, button])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 10
        text.setCustomSpacing(16, after: status)
        let row = NSStackView(views: [icon, text])
        row.alignment = .top
        row.spacing = 20
        row.edgeInsets = NSEdgeInsets(top: 34, left: 26, bottom: 26, right: 26)
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true
        window.contentView = row
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    func applicationDidBecomeActive(_ note: Notification) { refresh() }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    func refresh() {
        if isTranslocated {
            status.stringValue = Text.translocated
            button.isHidden = true
            return
        }
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionID) { state, error in
            DispatchQueue.main.async {
                if let state = state, error == nil {
                    self.status.stringValue = state.isEnabled ? Text.on : Text.off
                } else {
                    self.status.stringValue = Text.unknown
                }
            }
        }
    }

    @objc func openSettings() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionID) { error in
            guard error != nil else { return }
            DispatchQueue.main.async { self.status.stringValue = Text.openFailed }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.mainMenu = {
    let menu = NSMenu(), item = NSMenuItem()
    menu.addItem(item)
    let sub = NSMenu()
    sub.addItem(withTitle: "Quit \(Text.title)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    item.submenu = sub
    return menu
}()
app.run()
