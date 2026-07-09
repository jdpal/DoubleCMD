import AppKit
import WebKit

final class MainWindowController: NSWindowController {
    private let webView: WKWebView
    private let fileManager = FileManager.default
    private var leftDirectory = FileManager.default.homeDirectoryForCurrentUser
    private var rightDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    private var activePane = "left"

    init() {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        configuration.userContentController = contentController
        webView = WKWebView(frame: .zero, configuration: configuration)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "My Explorer"
        window.center()
        window.minSize = NSSize(width: 980, height: 640)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        super.init(window: window)

        contentController.add(self, name: "myExplorer")
        webView.navigationDelegate = self

        let controller = NSViewController()
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground")
        controller.view = NSView()
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor(calibratedRed: 0.84, green: 0.86, blue: 0.88, alpha: 1).cgColor
        controller.view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: controller.view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor)
        ])

        window.contentViewController = controller
        loadMockupShell()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func openSelected(_ sender: Any?) {
        post(action: "openSelected")
    }

    @objc func refresh(_ sender: Any?) {
        sendState()
    }

    @objc func focusLeftPane(_ sender: Any?) {
        activePane = "left"
        sendState()
    }

    @objc func focusRightPane(_ sender: Any?) {
        activePane = "right"
        sendState()
    }

    @objc func copySelected(_ sender: Any?) {
        post(action: "copy")
    }

    @objc func moveSelected(_ sender: Any?) {
        post(action: "move")
    }

    @objc func renameSelected(_ sender: Any?) {
        post(action: "rename")
    }

    @objc func deleteSelected(_ sender: Any?) {
        post(action: "delete")
    }

    private func loadMockupShell() {
        guard let url = Bundle.main.url(forResource: "browser-style-dual-pane", withExtension: "html") else {
            showError(NSError(domain: "MyExplorer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing browser-style-dual-pane.html"]))
            return
        }

        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private func post(action: String) {
        webView.evaluateJavaScript("window.MyExplorerApp && window.MyExplorerApp.invokeSelected('\(action)')")
    }

    private func sendState() {
        let state = AppState(
            activePane: activePane,
            addressPath: directory(for: activePane).path,
            favorites: favorites(),
            left: paneState(id: "left", title: "Left Pane", directory: leftDirectory, tabs: ["src", "docs"]),
            right: paneState(id: "right", title: "Right Pane", directory: rightDirectory, tabs: ["mockups", "build"])
        )

        do {
            let data = try JSONEncoder().encode(state)
            let json = String(decoding: data, as: UTF8.self)
            webView.evaluateJavaScript("window.MyExplorerApp && window.MyExplorerApp.render(\(json));")
        } catch {
            showError(error)
        }
    }

    private func paneState(id: String, title: String, directory: URL, tabs: [String]) -> PaneState {
        let urls = list(directory)
        let parent = FileEntry.parentEntry(for: directory)
        let entries = ([parent].compactMap { $0 } + urls.map { FileEntry(url: $0) }).map(entryState)
        return PaneState(
            id: id,
            title: title,
            tabNames: tabs,
            path: directory.path,
            entries: entries
        )
    }

    private func list(_ directory: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .contentTypeKey, .isHiddenKey]
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        )) ?? []

        return urls
            .filter { ((try? $0.resourceValues(forKeys: [.isHiddenKey]))?.isHidden ?? false) == false }
            .sorted { lhs, rhs in
                let left = FileEntry(url: lhs)
                let right = FileEntry(url: rhs)
                if left.isDirectory != right.isDirectory {
                    return left.isDirectory
                }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }

    private func entryState(_ entry: FileEntry) -> EntryState {
        EntryState(
            name: entry.name,
            path: entry.url.path,
            isDirectory: entry.isDirectory,
            size: sizeText(for: entry),
            modified: modifiedText(for: entry),
            iconClass: iconClass(for: entry),
            symbol: symbol(for: entry)
        )
    }

    private func sizeText(for entry: FileEntry) -> String {
        if entry.name == ".." { return "" }
        if entry.isDirectory { return "Folder" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: entry.byteCount ?? 0)
    }

    private func modifiedText(for entry: FileEntry) -> String {
        guard let modifiedAt = entry.modifiedAt else { return "" }
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedAt)
    }

    private func iconClass(for entry: FileEntry) -> String {
        if entry.name == ".." { return "back-icon" }
        if entry.isDirectory { return "folder-icon" }
        let ext = entry.url.pathExtension.lowercased()
        if ["swift", "pas", "pp", "sh", "js", "ts", "html", "css", "json", "xml"].contains(ext) { return "code-icon" }
        if ["md", "txt", "rtf"].contains(ext) { return "markdown-icon" }
        if ["png", "jpg", "jpeg", "gif", "icns", "svg"].contains(ext) { return "image-icon" }
        if ["zip", "dmg", "pkg", "tar", "gz"].contains(ext) { return "package-icon" }
        if ["app"].contains(ext) { return "app-icon" }
        return "doc-icon"
    }

    private func symbol(for entry: FileEntry) -> String {
        if entry.name == ".." { return "i-arrow-up" }
        if entry.isDirectory { return "i-folder" }
        let ext = entry.url.pathExtension.lowercased()
        if ["swift", "pas", "pp", "sh", "js", "ts", "html", "css", "json", "xml"].contains(ext) { return "i-code" }
        if ["app"].contains(ext) { return "i-app" }
        return "i-file"
    }

    private func favorites() -> [FavoriteState] {
        let home = fileManager.homeDirectoryForCurrentUser
        return [
            FavoriteState(title: "Desktop", symbol: "i-desktop", style: "desktop", path: home.appendingPathComponent("Desktop", isDirectory: true).path),
            FavoriteState(title: "Downloads", symbol: "i-download", style: "downloads", path: home.appendingPathComponent("Downloads", isDirectory: true).path),
            FavoriteState(title: "Documents", symbol: "i-file", style: "documents", path: home.appendingPathComponent("Documents", isDirectory: true).path),
            FavoriteState(title: "Projects", symbol: "i-folder", style: "projects", path: home.appendingPathComponent("Downloads/Development", isDirectory: true).path),
            FavoriteState(title: "iCloud Drive", symbol: "i-cloud", style: "cloud", path: home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true).path),
            FavoriteState(title: "Network", symbol: "i-network", style: "network", path: "/Network")
        ]
    }

    private func directory(for pane: String) -> URL {
        pane == "right" ? rightDirectory : leftDirectory
    }

    private func setDirectory(_ url: URL, for pane: String) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            NSSound.beep()
            return
        }

        if pane == "right" {
            rightDirectory = url.standardizedFileURL
        } else {
            leftDirectory = url.standardizedFileURL
        }
        activePane = pane
        sendState()
    }

    private func handle(_ action: String, pane: String, path: String?) {
        activePane = pane
        let selected = path.map { URL(fileURLWithPath: $0) }

        switch action {
        case "select":
            sendState()
        case "open", "openSelected":
            guard let selected else { return }
            let entry = FileEntry(url: selected)
            if entry.isDirectory {
                setDirectory(selected, for: pane)
            } else {
                NSWorkspace.shared.open(selected)
            }
        case "favorite":
            guard let selected else { return }
            setDirectory(selected, for: pane)
        case "parent":
            setDirectory(directory(for: pane).deletingLastPathComponent(), for: pane)
        case "home":
            setDirectory(fileManager.homeDirectoryForCurrentUser, for: pane)
        case "refresh":
            sendState()
        case "copy", "move":
            guard let selected else { return }
            let targetDirectory = directory(for: pane == "right" ? "left" : "right")
            let target = targetDirectory.appendingPathComponent(selected.lastPathComponent)
            do {
                if action == "copy" {
                    try fileManager.copyItem(at: selected, to: target)
                } else {
                    try fileManager.moveItem(at: selected, to: target)
                }
                sendState()
            } catch {
                showError(error)
            }
        case "delete":
            guard let selected else { return }
            do {
                var resultingURL: NSURL?
                try fileManager.trashItem(at: selected, resultingItemURL: &resultingURL)
                sendState()
            } catch {
                showError(error)
            }
        default:
            break
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "My Explorer"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension MainWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sendState()
    }
}

extension MainWindowController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard
            message.name == "myExplorer",
            let body = message.body as? [String: Any],
            let action = body["action"] as? String
        else { return }

        let pane = (body["pane"] as? String) ?? activePane
        let path = body["path"] as? String
        handle(action, pane: pane, path: path)
    }
}

private struct AppState: Encodable {
    let activePane: String
    let addressPath: String
    let favorites: [FavoriteState]
    let left: PaneState
    let right: PaneState
}

private struct FavoriteState: Encodable {
    let title: String
    let symbol: String
    let style: String
    let path: String
}

private struct PaneState: Encodable {
    let id: String
    let title: String
    let tabNames: [String]
    let path: String
    let entries: [EntryState]
}

private struct EntryState: Encodable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: String
    let modified: String
    let iconClass: String
    let symbol: String
}
