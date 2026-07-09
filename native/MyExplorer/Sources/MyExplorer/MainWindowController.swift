import AppKit

final class MainWindowController: NSWindowController {
    private let leftPane = FilePaneViewController(directory: FileManager.default.homeDirectoryForCurrentUser)
    private let rightPane = FilePaneViewController(directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true))
    private var activePane: FilePaneViewController

    init() {
        activePane = leftPane

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "My Explorer"
        window.center()
        window.minSize = NSSize(width: 860, height: 520)
        window.titlebarAppearsTransparent = false

        super.init(window: window)

        leftPane.delegate = self
        rightPane.delegate = self
        window.contentViewController = makeRootController()
        window.toolbar = makeToolbar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        leftPane.focus()
    }

    @objc func openSelected(_ sender: Any?) {
        activePane.openSelected()
    }

    @objc func refresh(_ sender: Any?) {
        leftPane.refresh()
        rightPane.refresh()
    }

    @objc func focusLeftPane(_ sender: Any?) {
        activePane = leftPane
        leftPane.focus()
    }

    @objc func focusRightPane(_ sender: Any?) {
        activePane = rightPane
        rightPane.focus()
    }

    @objc func copySelected(_ sender: Any?) {
        performFileOperation(.copy)
    }

    @objc func moveSelected(_ sender: Any?) {
        performFileOperation(.move)
    }

    @objc func renameSelected(_ sender: Any?) {
        guard let entry = activePane.selectedEntry, entry.name != ".." else { return }

        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Enter a new name for \(entry.name)."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.stringValue = entry.name
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trimmed = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let destination = entry.url.deletingLastPathComponent().appendingPathComponent(trimmed)
        do {
            try FileManager.default.moveItem(at: entry.url, to: destination)
            refresh(nil)
        } catch {
            present(error)
        }
    }

    @objc func deleteSelected(_ sender: Any?) {
        guard let entry = activePane.selectedEntry, entry.name != ".." else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \(entry.name)?"
        alert.informativeText = "This moves the selected item to the Trash."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: entry.url, resultingItemURL: &resultingURL)
            refresh(nil)
        } catch {
            present(error)
        }
    }

    private func makeRootController() -> NSViewController {
        let split = NSSplitViewController()
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        split.addSplitViewItem(NSSplitViewItem(viewController: leftPane))
        split.addSplitViewItem(NSSplitViewItem(viewController: rightPane))
        return split
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "main")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = true
        return toolbar
    }

    private enum FileOperation {
        case copy
        case move
    }

    private func performFileOperation(_ operation: FileOperation) {
        guard let entry = activePane.selectedEntry, entry.name != ".." else { return }
        let destinationPane = activePane === leftPane ? rightPane : leftPane
        let destination = destinationPane.directory.appendingPathComponent(entry.name)

        do {
            switch operation {
            case .copy:
                try FileManager.default.copyItem(at: entry.url, to: destination)
            case .move:
                try FileManager.default.moveItem(at: entry.url, to: destination)
            }
            refresh(nil)
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

extension MainWindowController: FilePaneViewControllerDelegate {
    func filePaneDidBecomeActive(_ pane: FilePaneViewController) {
        activePane = pane
    }

    func filePane(_ pane: FilePaneViewController, didRequestOpen entry: FileEntry) {
        activePane = pane
    }
}

extension MainWindowController: NSToolbarDelegate {
    private enum Item: String, CaseIterable {
        case open
        case copy
        case move
        case rename
        case delete
        case refresh

        var identifier: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Item.allCases.map(\.identifier) + [.flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("open"), .init("copy"), .init("move"), .flexibleSpace, .init("rename"), .init("delete"), .init("refresh")]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier.rawValue {
        case "open":
            configure(item, label: "Open", symbol: "arrow.up.forward.app", action: #selector(openSelected(_:)))
        case "copy":
            configure(item, label: "Copy", symbol: "doc.on.doc", action: #selector(copySelected(_:)))
        case "move":
            configure(item, label: "Move", symbol: "arrow.right.doc.on.clipboard", action: #selector(moveSelected(_:)))
        case "rename":
            configure(item, label: "Rename", symbol: "pencil", action: #selector(renameSelected(_:)))
        case "delete":
            configure(item, label: "Delete", symbol: "trash", action: #selector(deleteSelected(_:)))
        case "refresh":
            configure(item, label: "Refresh", symbol: "arrow.clockwise", action: #selector(refresh(_:)))
        default:
            return nil
        }

        return item
    }

    private func configure(_ item: NSToolbarItem, label: String, symbol: String, action: Selector) {
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = self
        item.action = action
    }
}
