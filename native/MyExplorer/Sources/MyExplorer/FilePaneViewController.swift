import AppKit
import UniformTypeIdentifiers

protocol FilePaneViewControllerDelegate: AnyObject {
    func filePaneDidBecomeActive(_ pane: FilePaneViewController)
    func filePane(_ pane: FilePaneViewController, didRequestOpen entry: FileEntry)
}

final class FilePaneViewController: NSViewController {
    weak var delegate: FilePaneViewControllerDelegate?

    private let fileManager = FileManager.default
    private let pathField = NSTextField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let formatter = ByteCountFormatter()
    private let dateFormatter = DateFormatter()

    private(set) var directory: URL
    private var entries: [FileEntry] = []

    var selectedEntry: FileEntry? {
        let row = tableView.selectedRow
        guard entries.indices.contains(row) else { return nil }
        return entries[row]
    }

    init(directory: URL) {
        self.directory = directory
        super.init(nibName: nil, bundle: nil)
        formatter.countStyle = .file
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        pathField.isEditable = true
        pathField.isBordered = true
        pathField.bezelStyle = .roundedBezel
        pathField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        pathField.target = self
        pathField.action = #selector(pathSubmitted(_:))
        pathField.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnSelection = false
        tableView.allowsMultipleSelection = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openDoubleClicked(_:))

        addColumn(identifier: "name", title: "Name", width: 260)
        addColumn(identifier: "size", title: "Size", width: 90)
        addColumn(identifier: "kind", title: "Kind", width: 130)
        addColumn(identifier: "modified", title: "Modified", width: 160)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(pathField)
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            pathField.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            pathField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            pathField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            pathField.heightAnchor.constraint(equalToConstant: 28),

            scrollView.topAnchor.constraint(equalTo: pathField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refresh()
    }

    func refresh() {
        pathField.stringValue = directory.path

        var nextEntries: [FileEntry] = []
        if let parent = FileEntry.parentEntry(for: directory) {
            nextEntries.append(parent)
        }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .contentTypeKey, .isHiddenKey]
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        )) ?? []

        let visible = urls.filter { url in
            ((try? url.resourceValues(forKeys: [.isHiddenKey]))?.isHidden ?? false) == false
        }

        nextEntries += visible
            .map { FileEntry(url: $0) }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        entries = nextEntries
        tableView.reloadData()
        if !entries.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: min(1, entries.count - 1)), byExtendingSelection: false)
        }
    }

    func openSelected() {
        guard let entry = selectedEntry else { return }
        open(entry)
    }

    func focus() {
        view.window?.makeFirstResponder(tableView)
        delegate?.filePaneDidBecomeActive(self)
    }

    func navigate(to url: URL) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            NSSound.beep()
            return
        }

        directory = url.standardizedFileURL
        refresh()
    }

    private func addColumn(identifier: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        tableView.addTableColumn(column)
    }

    private func open(_ entry: FileEntry) {
        if entry.isDirectory {
            navigate(to: entry.url)
        } else {
            NSWorkspace.shared.open(entry.url)
        }
        delegate?.filePane(self, didRequestOpen: entry)
    }

    @objc private func pathSubmitted(_ sender: NSTextField) {
        navigate(to: URL(fileURLWithPath: sender.stringValue, isDirectory: true))
    }

    @objc private func openDoubleClicked(_ sender: NSTableView) {
        openSelected()
    }
}

extension FilePaneViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        delegate?.filePaneDidBecomeActive(self)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row), let tableColumn else { return nil }
        let entry = entries[row]
        let identifier = tableColumn.identifier

        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        let textField: NSTextField
        if let existing = cell.textField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingMiddle
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        switch identifier.rawValue {
        case "name":
            textField.stringValue = entry.name
            textField.font = entry.isDirectory ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13)
        case "size":
            textField.stringValue = entry.isDirectory ? "" : formatter.string(fromByteCount: entry.byteCount ?? 0)
            textField.font = .systemFont(ofSize: 13)
        case "kind":
            textField.stringValue = entry.typeDescription
            textField.font = .systemFont(ofSize: 13)
        case "modified":
            textField.stringValue = entry.modifiedAt.map(dateFormatter.string(from:)) ?? ""
            textField.font = .systemFont(ofSize: 13)
        default:
            textField.stringValue = ""
        }

        return cell
    }
}
