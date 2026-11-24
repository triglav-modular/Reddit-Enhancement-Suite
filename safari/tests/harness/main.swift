// Loads the Safari build into WebKit's own web-extension runtime
// (WKWebExtensionController, the engine Safari's extensions run on) and checks
// it against an archived old.reddit page served at its real URL.
//
//   harness EXTENSION_DIR FIXTURE_HTML PAGE_URL
//
// Safari's automation sessions load no extensions, so this is the automated
// check. The page's own scripts and images come from the network; Reddit's
// API answers a logged-out client, as old.reddit does today, with a login wall.

import AppKit
import WebKit

setvbuf(stdout, nil, _IOLBF, 0)

let args = CommandLine.arguments
if args.count != 4 || URL(string: args[3]) == nil {
    print("usage: harness EXTENSION_DIR FIXTURE_HTML PAGE_URL")
    exit(2)
}
let pageURL = URL(string: args[3])!
let extensionDir = URL(fileURLWithPath: args[1], isDirectory: true)
let fixture: String? = args[2] == "-" ? nil : try! String(contentsOfFile: args[2], encoding: .utf8)
let safariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.2 Safari/605.1.15"

final class Tab: NSObject, WKWebExtensionTab {
    let webView: WKWebView
    weak var window: Window?
    init(webView: WKWebView) { self.webView = webView }
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { window }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { 0 }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }
    func url(for context: WKWebExtensionContext) -> URL? { webView.url }
    func title(for context: WKWebExtensionContext) -> String? { webView.title }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !webView.isLoading }
    func isSelected(for context: WKWebExtensionContext) -> Bool { true }
}

final class Window: NSObject, WKWebExtensionWindow {
    let tab: Tab
    let frame: CGRect
    init(tab: Tab, frame: CGRect) { self.tab = tab; self.frame = frame }
    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { [tab] }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { tab }
    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState { .normal }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }
    func frame(for context: WKWebExtensionContext) -> CGRect { frame }
    func screenFrame(for context: WKWebExtensionContext) -> CGRect { CGRect(x: 0, y: 0, width: 1920, height: 1080) }
}

@MainActor
final class Harness: NSObject, WKWebExtensionControllerDelegate, WKNavigationDelegate, WKDownloadDelegate {
    var controller: WKWebExtensionController!
    var context: WKWebExtensionContext!
    var webView: WKWebView!
    var tab: Tab!
    var window: Window?
    var hostWindow: NSWindow!
    var openedTabs: [URL] = []
    var openedWindows: [[URL]] = []
    var permissionPrompts: [String] = []
    var downloads: [(name: String, bytes: Int)] = []
    var downloadFiles: [ObjectIdentifier: (name: String, url: URL)] = [:]
    var extensionFrames: [WKFrameInfo] = []
    var navigationDone = false
    var failures = 0

    func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if ok { print("PASS \(name)") } else { failures += 1; print("FAIL \(name)\(detail().isEmpty ? "" : ": \(detail())")") }
    }

    func setUp() async throws {
        let ext = try await WKWebExtension(resourceBaseURL: extensionDir)
        for error in ext.errors { print("manifest: \(error.localizedDescription)") }
        context = WKWebExtensionContext(for: ext)
        context.isInspectable = true
        // What a person grants in Safari: the extension's permissions, and
        // "Always Allow on Every Website" for its Reddit match patterns.
        for permission in ext.requestedPermissions { context.setPermissionStatus(.grantedExplicitly, for: permission) }
        for pattern in ext.allRequestedMatchPatterns { context.setPermissionStatus(.grantedExplicitly, for: pattern) }

        controller = WKWebExtensionController(configuration: .nonPersistent())
        controller.delegate = self
        try controller.load(context)

        let configuration = WKWebViewConfiguration()
        configuration.webExtensionController = controller
        configuration.websiteDataStore = controller.configuration.defaultWebsiteDataStore
        let frame = CGRect(x: 0, y: 0, width: 1280, height: 900)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.customUserAgent = safariUA
        webView.navigationDelegate = self
        webView.isInspectable = true
        let selector = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        if webView.responds(to: selector) { webView.perform(selector, with: false) }

        // Off every screen and ordered in, so WebKit treats it as a live window.
        hostWindow = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1280, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        hostWindow.contentView = webView
        hostWindow.orderFrontRegardless()

        tab = Tab(webView: webView)
        window = Window(tab: tab, frame: frame)
        tab.window = window
        controller.didOpenWindow(window!)
        controller.didFocusWindow(window)
        controller.didOpenTab(tab)
        controller.didActivateTab(tab, previousActiveTab: nil)
    }

    // MARK: page helpers

    func js(_ body: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        try await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
    }

    func waitFor(_ expression: String, seconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let ok = try? await js("return !!(\(expression))") as? Bool, ok { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }

    /// Asks the harness content script, which shares RES's isolated world.
    func bridge(_ op: String, _ arg: Any = NSNull()) async throws -> Any? {
        let json = try await js("""
            return await new Promise((resolve, reject) => {
                const id = Math.random().toString(36).slice(2);
                const onMessage = e => {
                    if (e.source !== window || !e.data || e.data.resHarness !== 'response' || e.data.id !== id) return;
                    removeEventListener('message', onMessage);
                    resolve(JSON.stringify(e.data.result ?? null));
                };
                addEventListener('message', onMessage);
                postMessage({ resHarness: 'request', id, op, arg }, '*');
                setTimeout(() => reject(new Error('no answer from the harness content script')), 15000);
            });
            """, ["op": op, "arg": arg]) as? String ?? "null"
        return try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
    }

    func send(_ type: String, _ data: Any) async throws -> Any? {
        let reply = try await bridge("send", ["type": type, "data": data]) as? [String: Any]
        if let error = reply?["error"] { throw NSError(domain: "RES", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(error)"]) }
        return reply?["data"]
    }

    // MARK: the checks

    func run() async {
        do { try await setUp() } catch { print("FAIL setup: \(error)"); exit(1) }

        if let fixture { webView.loadSimulatedRequest(URLRequest(url: pageURL), responseHTML: fixture) } else { webView.load(URLRequest(url: pageURL)) }
        let loaded = await waitFor("document.readyState === 'complete'", seconds: 30)
        check("page loads", loaded)

        for error in context.errors { print("context error: \(error.localizedDescription)") }
        let injected = await waitFor("document.documentElement.dataset.resHarness", seconds: 15)
        check("WebKit injects the extension's content scripts", injected)
        let resRan = await waitFor("document.documentElement.classList.contains('res')", seconds: 30)
        let rootState = (try? await js("return document.documentElement.className + ' | ' + (document.documentElement.getAttribute('res-warning') || '')")) as? String ?? ""
        check("content script runs and RES initialises", resRan, rootState)
        let gear = await waitFor("document.querySelector('#RESSettingsButton')", seconds: 20)
        check("RES menu gear is added to the header", gear)

        let expandos = await waitFor("document.querySelectorAll('.expando-button').length >= 5", seconds: 20)
        let expandoCount = (try? await js("return document.querySelectorAll('.expando-button').length")) as? Int ?? 0
        check("showImages adds expando buttons", expandos, "\(expandoCount) found")

        // Messaging and storage through the background service worker.
        do {
            let key = "harness.storage.\(Int(Date().timeIntervalSince1970))"
            let swapped = try await send("storage-cas", [key, NSNull(), NSNull(), "stored"]) as? Bool
            check("background storage compare-and-swap", swapped == true, "\(String(describing: swapped))")
        } catch { check("background storage compare-and-swap", false, "\(error)") }

        // Visits: Safari has no history API, so RES keeps its own record.
        do {
            let pageVisited = await waitForVisit(pageURL.absoluteString)
            check("the Reddit page itself is recorded as visited", pageVisited)
            let altHost = pageURL.absoluteString.replacingOccurrences(of: "old.reddit.com", with: "www.reddit.com") + "?sort=new"
            let altVisited = try await send("isURLVisited", altHost) as? Bool
            check("a Reddit URL matches on another host and query", altVisited == true, "\(String(describing: altVisited))")
            let neverVisited = try await send("isURLVisited", "https://example.com/never-visited-\(UUID().uuidString)") as? Bool
            check("an unseen URL is not visited", neverVisited == false, "\(String(describing: neverVisited))")
            let followed = try await js("""
                const link = document.querySelector('.thing.link:not(.promoted) a.title');
                link.addEventListener('click', e => e.preventDefault(), { once: true });
                link.click();
                return link.href;
                """) as? String ?? ""
            let linkVisited = await waitForVisit(followed)
            check("a followed link is recorded as visited", linkVisited, followed)
        } catch { check("visits", false, "\(error)") }

        // Expando and download.
        do {
            let opened = try await js("""
                const button = [...document.querySelectorAll('.thing.link:not(.promoted) .expando-button')]
                    .find(b => /i\\.redd\\.it/.test(b.closest('.thing').dataset.url || ''));
                if (!button) return '';
                button.click();
                return button.closest('.thing').dataset.url;
                """) as? String ?? ""
            let media = await waitFor("document.querySelector('.res-expando-box .res-media-controls-download')", seconds: 20)
            check("an i.redd.it image expands with media controls", media, opened)
            if media {
                _ = try await js("document.querySelector('.res-expando-box .res-media-controls-download').click()")
                let deadline = Date().addingTimeInterval(60)
                while downloads.isEmpty && Date() < deadline { try? await Task.sleep(nanoseconds: 250_000_000) }
                let first = downloads.first
                check("the download button saves the image under the post's title",
                      (first?.bytes ?? 0) > 10_000 && (first?.name.hasSuffix(".jpeg") ?? false),
                      first.map { "\($0.name), \($0.bytes) bytes" } ?? "no download")
            }
        } catch { check("expando", false, "\(error)") }

        // Toolbar button: the subreddit style toggle, on a subreddit with its own style.
        let action = context.action(for: tab)
        check("the toolbar button is enabled as the subreddit style toggle",
              action?.isEnabled == true && action?.label == "Subreddit Style On",
              "enabled \(String(describing: action?.isEnabled)), label \(action?.label ?? "-")")

        // Settings console: the extension's options page framed into Reddit.
        do {
            _ = try await js("location.hash = '#res:settings'")
            let framed = await waitFor("document.querySelector('iframe[src*=\"options.html\"]')", seconds: 20)
            check("the settings console opens in the page", framed)
            if framed {
                let deadline = Date().addingTimeInterval(20)
                var text = ""
                while Date() < deadline {
                    if let frame = extensionFrames.last,
                       let body = try? await webView.evaluateJavaScript("document.body ? document.body.innerText : ''", in: frame, contentWorld: .page) as? String,
                       body.contains("Settings") || body.count > 500 {
                        text = body; break
                    }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                check("the settings console renders its modules", text.count > 500,
                      "frames seen: \(extensionFrames.count), text: \(text.prefix(120))")
            }
        } catch { check("settings console", false, "\(error)") }

        finish()
    }

    func waitForVisit(_ url: String) async -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let visited = try? await send("isURLVisited", url) as? Bool, visited { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    func finish() {
        Task { @MainActor in
            if let errors = try? await bridge("errors") as? [String: Any] {
                let content = errors["content"] as? [String] ?? []
                let background = errors["background"] as? [String] ?? []
                // "Script error." is the page's own cross-origin scripts; WebKit hides their text.
                let report = (content.map { "content: \($0)" } + background.map { "background: \($0)" })
                    .filter { !$0.hasSuffix("error: Script error.") }
                    .map { $0.split(separator: "\n").prefix(2).joined(separator: " <- ") }
                for (line, count) in Dictionary(grouping: report, by: { $0 }).mapValues(\.count).sorted(by: { $0.key < $1.key }) {
                    print("logged \(count)x \(line.prefix(300))")
                }
                // A missing API or global shows up as one of these; Reddit's
                // login wall only produces failed requests.
                let fatal = (content + background).filter {
                    $0.contains("ReferenceError") || $0.contains("Can't find variable") || $0.contains("is not a function")
                        || $0.contains("undefined is not an object") || $0.contains("not supported")
                }
                check("no missing-API errors in RES's content script or background", fatal.isEmpty, fatal.joined(separator: " | ").prefix(600).description)
            } else {
                check("error report from the harness", false, "unavailable")
            }
            if !openedTabs.isEmpty { print("info: tabs opened: \(openedTabs)") }
            if !permissionPrompts.isEmpty { print("info: permission prompts: \(permissionPrompts)") }
            print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
            exit(failures == 0 ? 0 : 1)
        }
    }

    // MARK: WKWebExtensionControllerDelegate

    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] { window.map { [$0] } ?? [] }
    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { window }
    func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration, for extensionContext: WKWebExtensionContext, completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void) {
        if let url = configuration.url { openedTabs.append(url) }
        completionHandler(nil, nil)
    }
    func webExtensionController(_ controller: WKWebExtensionController, openNewWindowUsing configuration: WKWebExtension.WindowConfiguration, for extensionContext: WKWebExtensionContext, completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void) {
        openedWindows.append(configuration.tabURLs)
        completionHandler(nil, nil)
    }
    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        permissionPrompts.append(permissions.map(\.rawValue).sorted().joined(separator: ","))
        completionHandler([], nil)
    }
    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        permissionPrompts.append(matchPatterns.map(\.description).sorted().joined(separator: ","))
        completionHandler([], nil)
    }

    // MARK: WKNavigationDelegate and downloads

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if let frame = navigationAction.targetFrame, !frame.isMainFrame,
           let scheme = navigationAction.request.url?.scheme, scheme.hasSuffix("-extension") {
            extensionFrames.append(frame)
        }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("res-harness-\(UUID().uuidString)-\(suggestedFilename)")
        downloadFiles[ObjectIdentifier(download)] = (suggestedFilename, url)
        return url
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let file = downloadFiles[ObjectIdentifier(download)] else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.url.path)[.size] as? Int) ?? 0
        downloads.append((file.name, size))
        try? FileManager.default.removeItem(at: file.url)
    }
    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        print("info: download failed: \(error)")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    let harness = Harness()
    // A hard stop, so a hang fails instead of waiting forever.
    DispatchQueue.main.asyncAfter(deadline: .now() + 240) { print("FAIL timed out"); exit(1) }
    await harness.run()
}
app.run()
