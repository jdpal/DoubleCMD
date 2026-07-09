import AppKit
import WebKit

final class MyExplorerWebView: WKWebView {
    private var possibleWindowDragEvent: NSEvent?
    private var possibleWindowDragStart = NSPoint.zero

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if bounds.height - location.y <= 38 {
            possibleWindowDragEvent = event
            possibleWindowDragStart = event.locationInWindow
        } else {
            possibleWindowDragEvent = nil
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let dragEvent = possibleWindowDragEvent {
            let deltaX = event.locationInWindow.x - possibleWindowDragStart.x
            let deltaY = event.locationInWindow.y - possibleWindowDragStart.y
            if hypot(deltaX, deltaY) > 3 {
                possibleWindowDragEvent = nil
                window?.performDrag(with: dragEvent)
                return
            }
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        possibleWindowDragEvent = nil
        super.mouseUp(with: event)
    }
}

final class MainWindowController: NSWindowController {
    private let webView: WKWebView
    private let fileManager = FileManager.default
    private var leftDirectory = FileManager.default.homeDirectoryForCurrentUser
    private var rightDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    private var activePane = "left"
    private var leftSearchQuery = ""
    private var rightSearchQuery = ""
    private let customFavoritesKey = "MyExplorer.CustomFavorites"
    private var workspaces: [WorkspaceTab] = []
    private var activeWorkspaceID = "workspace-1"

    init() {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        configuration.userContentController = contentController
        webView = MyExplorerWebView(frame: .zero, configuration: configuration)

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
        setupDefaultWorkspaces()
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
            workspaces: workspaceStates(),
            favorites: favorites(),
            left: paneState(id: "left", title: "Left Pane", directory: leftDirectory, tabs: ["src", "docs"], searchQuery: leftSearchQuery),
            right: paneState(id: "right", title: "Right Pane", directory: rightDirectory, tabs: ["mockups", "build"], searchQuery: rightSearchQuery)
        )

        do {
            let data = try JSONEncoder().encode(state)
            let json = String(decoding: data, as: UTF8.self)
            webView.evaluateJavaScript("window.MyExplorerApp && window.MyExplorerApp.render(\(json));")
        } catch {
            showError(error)
        }
    }

    private func paneState(id: String, title: String, directory: URL, tabs: [String], searchQuery: String) -> PaneState {
        let entries: [EntryState]
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let urls = list(directory)
            let parent = FileEntry.parentEntry(for: directory)
            entries = ([parent].compactMap { $0 } + urls.map { FileEntry(url: $0) }).map { entryState($0) }
        } else {
            entries = recursiveSearch(in: directory, query: searchQuery).map { url in
                let relativeName = relativePath(for: url, under: directory)
                return entryState(FileEntry(url: url), displayName: relativeName)
            }
        }
        return PaneState(
            id: id,
            title: title,
            tabNames: tabs,
            path: directory.path,
            searchQuery: searchQuery,
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

    private func recursiveSearch(in directory: URL, query: String) -> [URL] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .contentTypeKey, .isHiddenKey]
        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        )

        var matches: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent.localizedCaseInsensitiveContains(normalized) {
                matches.append(url)
            }
        }

        return matches.sorted { lhs, rhs in
            let left = FileEntry(url: lhs)
            let right = FileEntry(url: rhs)
            if left.isDirectory != right.isDirectory {
                return left.isDirectory
            }
            return relativePath(for: lhs, under: directory).localizedStandardCompare(relativePath(for: rhs, under: directory)) == .orderedAscending
        }
    }

    private func relativePath(for url: URL, under directory: URL) -> String {
        let base = directory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base) else { return path }
        let startIndex = path.index(path.startIndex, offsetBy: base.count)
        let relative = path[startIndex...].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? url.lastPathComponent : String(relative)
    }

    private func entryState(_ entry: FileEntry, displayName: String? = nil) -> EntryState {
        EntryState(
            name: displayName ?? entry.name,
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
            FavoriteState(title: "Network", symbol: "i-network", style: "network", path: networkDirectory().path)
        ] + customFavorites()
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
            rightSearchQuery = ""
        } else {
            leftDirectory = url.standardizedFileURL
            leftSearchQuery = ""
        }
        activePane = pane
        saveCurrentWorkspace()
        sendState()
    }

    private func handle(_ action: String, pane: String, path: String?, command: String? = nil, tabID: String? = nil) {
        activePane = pane
        let selected = path.map { URL(fileURLWithPath: $0) }

        switch action {
        case "select":
            return
        case "open", "openSelected":
            guard let selected else { return }
            let entry = FileEntry(url: selected)
            if entry.isDirectory {
                setDirectory(selected, for: pane)
            } else {
                NSWorkspace.shared.open(selected)
            }
        case "edit":
            guard let selected else { return }
            edit(selected, pane: pane)
        case "favorite":
            guard let selected else { return }
            setDirectory(selected, for: pane)
        case "addFavorite":
            addFavorite(directory(for: activePane))
        case "searchPane":
            setSearchQuery(command ?? "", for: pane)
        case "workspaceNew":
            createWorkspace()
        case "workspaceSwitch":
            guard let tabID else { return }
            switchWorkspace(to: tabID)
        case "workspaceClose":
            guard let tabID else { return }
            closeWorkspace(tabID)
        case "parent":
            setDirectory(directory(for: pane).deletingLastPathComponent(), for: pane)
        case "home":
            setDirectory(fileManager.homeDirectoryForCurrentUser, for: pane)
        case "refresh":
            sendState()
        case "disk":
            setDirectory(URL(fileURLWithPath: "/", isDirectory: true), for: pane)
        case "network":
            setDirectory(networkDirectory(), for: pane)
        case "favorites":
            setDirectory(fileManager.homeDirectoryForCurrentUser, for: pane)
        case "tools", "more":
            showTools()
        case "search":
            showSearch()
        case "terminal":
            openTerminal(command: command)
        case "commandLine":
            runCommandLine(command)
        case "mkdir":
            makeDirectory(in: pane)
        case "rename":
            guard let selected else { return }
            rename(selected, pane: pane)
        case "copy", "move":
            guard let selected, canOperate(on: selected) else { return }
            let targetDirectory = directory(for: pane == "right" ? "left" : "right")
            let target = targetDirectory.appendingPathComponent(selected.lastPathComponent)
            let operation = action == "copy" ? "Copy" : "Move"
            guard confirmFileOperation(
                title: "\(operation) Item",
                message: "\(operation) \"\(selected.lastPathComponent)\" to:\n\(targetDirectory.path)",
                confirmTitle: operation
            ) else { return }
            guard !fileManager.fileExists(atPath: target.path) else {
                showMessage(title: "\(operation) Item", message: "An item named \"\(selected.lastPathComponent)\" already exists in the destination.")
                return
            }
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
            guard let selected, canOperate(on: selected) else { return }
            guard confirmFileOperation(
                title: "Move to Trash",
                message: "Move \"\(selected.lastPathComponent)\" to Trash?",
                confirmTitle: "Move to Trash"
            ) else { return }
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

    private func canOperate(on url: URL) -> Bool {
        guard url.lastPathComponent != ".." else {
            NSSound.beep()
            return false
        }
        guard fileManager.fileExists(atPath: url.path) else {
            showMessage(title: "My Explorer", message: "The selected item no longer exists.")
            sendState()
            return false
        }
        return true
    }

    private func confirmFileOperation(title: String, message: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func edit(_ url: URL, pane: String) {
        let entry = FileEntry(url: url)
        if entry.isDirectory {
            setDirectory(url, for: pane)
            return
        }

        if let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: configuration)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func networkDirectory() -> URL {
        let network = URL(fileURLWithPath: "/Network", isDirectory: true)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: network.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return network
        }
        return URL(fileURLWithPath: "/Volumes", isDirectory: true)
    }

    private func setSearchQuery(_ query: String, for pane: String) {
        if pane == "right" {
            rightSearchQuery = query
        } else {
            leftSearchQuery = query
        }
        saveCurrentWorkspace()
        sendState()
    }

    private func setupDefaultWorkspaces() {
        let home = fileManager.homeDirectoryForCurrentUser
        workspaces = [
            WorkspaceTab(
                id: "workspace-1",
                title: "Compare: Project Files",
                symbol: "i-folder",
                leftDirectory: home,
                rightDirectory: home.appendingPathComponent("Downloads", isDirectory: true),
                activePane: "left",
                leftSearchQuery: "",
                rightSearchQuery: ""
            ),
            WorkspaceTab(
                id: "workspace-2",
                title: "Downloads Review",
                symbol: "i-download",
                leftDirectory: home.appendingPathComponent("Downloads", isDirectory: true),
                rightDirectory: home.appendingPathComponent("Downloads", isDirectory: true),
                activePane: "right",
                leftSearchQuery: "",
                rightSearchQuery: ""
            ),
            WorkspaceTab(
                id: "workspace-3",
                title: "Documents",
                symbol: "i-file",
                leftDirectory: home.appendingPathComponent("Documents", isDirectory: true),
                rightDirectory: home.appendingPathComponent("Downloads", isDirectory: true),
                activePane: "left",
                leftSearchQuery: "",
                rightSearchQuery: ""
            )
        ]
        loadWorkspace(workspaces[0])
    }

    private func workspaceStates() -> [WorkspaceState] {
        workspaces.map {
            WorkspaceState(id: $0.id, title: $0.title, symbol: $0.symbol, isActive: $0.id == activeWorkspaceID)
        }
    }

    private func currentWorkspaceIndex() -> Int? {
        workspaces.firstIndex { $0.id == activeWorkspaceID }
    }

    private func saveCurrentWorkspace() {
        guard let index = currentWorkspaceIndex() else { return }
        workspaces[index].leftDirectory = leftDirectory
        workspaces[index].rightDirectory = rightDirectory
        workspaces[index].activePane = activePane
        workspaces[index].leftSearchQuery = leftSearchQuery
        workspaces[index].rightSearchQuery = rightSearchQuery
    }

    private func loadWorkspace(_ workspace: WorkspaceTab) {
        activeWorkspaceID = workspace.id
        leftDirectory = workspace.leftDirectory
        rightDirectory = workspace.rightDirectory
        activePane = workspace.activePane
        leftSearchQuery = workspace.leftSearchQuery
        rightSearchQuery = workspace.rightSearchQuery
    }

    private func switchWorkspace(to id: String) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        saveCurrentWorkspace()
        loadWorkspace(workspace)
        sendState()
    }

    private func createWorkspace() {
        saveCurrentWorkspace()
        let id = "workspace-\((workspaces.map { Int($0.id.replacingOccurrences(of: "workspace-", with: "")) ?? 0 }.max() ?? 0) + 1)"
        let title = "Tab \(workspaces.count + 1)"
        let workspace = WorkspaceTab(
            id: id,
            title: title,
            symbol: "i-folder",
            leftDirectory: leftDirectory,
            rightDirectory: rightDirectory,
            activePane: activePane,
            leftSearchQuery: leftSearchQuery,
            rightSearchQuery: rightSearchQuery
        )
        workspaces.append(workspace)
        loadWorkspace(workspace)
        sendState()
    }

    private func closeWorkspace(_ id: String) {
        guard workspaces.count > 1, let index = workspaces.firstIndex(where: { $0.id == id }) else {
            NSSound.beep()
            return
        }
        let closingActiveWorkspace = id == activeWorkspaceID
        workspaces.remove(at: index)
        if closingActiveWorkspace {
            let nextIndex = min(index, workspaces.count - 1)
            loadWorkspace(workspaces[nextIndex])
        }
        sendState()
    }

    private func customFavorites() -> [FavoriteState] {
        let paths = UserDefaults.standard.stringArray(forKey: customFavoritesKey) ?? []
        return paths.compactMap { path in
            let url = URL(fileURLWithPath: path, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            let title = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
            return FavoriteState(title: title, symbol: "i-star", style: "custom", path: url.path)
        }
    }

    private func addFavorite(_ url: URL) {
        let path = url.standardizedFileURL.path
        var paths = UserDefaults.standard.stringArray(forKey: customFavoritesKey) ?? []
        guard !paths.contains(path) else {
            NSSound.beep()
            return
        }
        paths.append(path)
        UserDefaults.standard.set(paths, forKey: customFavoritesKey)
        sendState()
    }

    private func openTerminal(command: String?) {
        let directory = directory(for: activePane).path
        let trimmedCommand = command?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cdCommand = "cd \(shellEscaped(directory))"
        let terminalCommand = [cdCommand, trimmedCommand].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: "; ")
        let script = "tell application \"Terminal\" to do script \(appleScriptString(terminalCommand))"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if error != nil {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        }
    }

    private func runCommandLine(_ command: String?) {
        let trimmed = command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            openTerminal(command: nil)
            return
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let pathURL = URL(fileURLWithPath: expanded, relativeTo: directory(for: activePane)).standardizedFileURL
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: pathURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            setDirectory(pathURL, for: activePane)
        } else {
            openTerminal(command: trimmed)
        }
    }

    private func shellEscaped(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func makeDirectory(in pane: String) {
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Create a folder in \(directory(for: pane).path)."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.stringValue = "New Folder"
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        do {
            try fileManager.createDirectory(at: directory(for: pane).appendingPathComponent(name), withIntermediateDirectories: false)
            sendState()
        } catch {
            showError(error)
        }
    }

    private func rename(_ url: URL, pane: String) {
        guard url.lastPathComponent != ".." else { return }

        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Enter a new name for \(url.lastPathComponent)."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.stringValue = url.lastPathComponent
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        do {
            try fileManager.moveItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent(name))
            sendState()
        } catch {
            showError(error)
        }
    }

    private func showSearch() {
        let alert = NSAlert()
        alert.messageText = "Search"
        alert.informativeText = "Search in \(directory(for: activePane).path)."
        alert.addButton(withTitle: "Search")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        input.placeholderString = "File or folder name"
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let query = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        showSearchResults(matching: query, in: directory(for: activePane))
    }

    private func showTools() {
        let alert = NSAlert()
        alert.messageText = "Commander Tools"
        alert.informativeText = "Choose a tool for the current left and right panes."
        alert.addButton(withTitle: "Compare Panes")
        alert.addButton(withTitle: "Search Active Pane")
        alert.addButton(withTitle: "Open Terminal")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            comparePanes()
        case .alertSecondButtonReturn:
            showSearch()
        case .alertThirdButtonReturn:
            openTerminal(command: nil)
        default:
            break
        }
    }

    private func comparePanes() {
        let leftEntries = list(leftDirectory).map { FileEntry(url: $0) }
        let rightEntries = list(rightDirectory).map { FileEntry(url: $0) }
        let leftByName = Dictionary(uniqueKeysWithValues: leftEntries.map { ($0.name, $0) })
        let rightByName = Dictionary(uniqueKeysWithValues: rightEntries.map { ($0.name, $0) })
        let leftNames = Set(leftByName.keys)
        let rightNames = Set(rightByName.keys)
        let leftOnly = leftNames.subtracting(rightNames).sorted()
        let rightOnly = rightNames.subtracting(leftNames).sorted()
        let changed = leftNames.intersection(rightNames).filter { name in
            guard let left = leftByName[name], let right = rightByName[name] else { return false }
            if left.isDirectory != right.isDirectory { return true }
            if left.byteCount != right.byteCount { return true }
            guard let leftDate = left.modifiedAt, let rightDate = right.modifiedAt else { return false }
            return abs(leftDate.timeIntervalSince(rightDate)) > 1
        }.sorted()

        var lines = [
            "Left: \(leftDirectory.path)",
            "Right: \(rightDirectory.path)",
            "",
            "\(leftOnly.count) only on left",
            "\(rightOnly.count) only on right",
            "\(changed.count) changed in both"
        ]

        appendPreview(title: "Only on left", names: leftOnly, to: &lines)
        appendPreview(title: "Only on right", names: rightOnly, to: &lines)
        appendPreview(title: "Changed", names: changed, to: &lines)

        let alert = NSAlert()
        alert.messageText = "Compare Results"
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func appendPreview(title: String, names: [String], to lines: inout [String]) {
        guard !names.isEmpty else { return }
        lines.append("")
        lines.append("\(title):")
        lines.append(contentsOf: names.prefix(8).map { "  \($0)" })
        if names.count > 8 {
            lines.append("  ... \(names.count - 8) more")
        }
    }

    private func showSearchResults(matching query: String, in scope: URL) {
        let enumerator = fileManager.enumerator(
            at: scope,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        var matches: [URL] = []

        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent.localizedCaseInsensitiveContains(query) {
                matches.append(url)
            }
            if matches.count >= 50 { break }
        }

        let alert = NSAlert()
        alert.messageText = "Search Results"
        if matches.isEmpty {
            alert.informativeText = "No matches for \"\(query)\" in \(scope.path)."
        } else {
            let resultLines = matches.prefix(30).map { $0.path }
            let suffix = matches.count > 30 ? "\n... \(matches.count - 30) more" : ""
            alert.informativeText = resultLines.joined(separator: "\n") + suffix
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        let command = body["command"] as? String
        let tabID = body["tabID"] as? String
        handle(action, pane: pane, path: path, command: command, tabID: tabID)
    }
}

private struct AppState: Encodable {
    let activePane: String
    let addressPath: String
    let workspaces: [WorkspaceState]
    let favorites: [FavoriteState]
    let left: PaneState
    let right: PaneState
}

private struct WorkspaceTab {
    let id: String
    var title: String
    var symbol: String
    var leftDirectory: URL
    var rightDirectory: URL
    var activePane: String
    var leftSearchQuery: String
    var rightSearchQuery: String
}

private struct WorkspaceState: Encodable {
    let id: String
    let title: String
    let symbol: String
    let isActive: Bool
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
    let searchQuery: String
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
