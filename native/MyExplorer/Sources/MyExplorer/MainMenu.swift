import AppKit

enum MainMenu {
    static func install() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About My Explorer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit My Explorer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "Open", action: #selector(MainWindowController.openSelected(_:)), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Copy to Other Pane", action: #selector(MainWindowController.copySelected(_:)), keyEquivalent: "c")
        fileMenu.addItem(withTitle: "Move to Other Pane", action: #selector(MainWindowController.moveSelected(_:)), keyEquivalent: "m")
        fileMenu.addItem(withTitle: "Rename", action: #selector(MainWindowController.renameSelected(_:)), keyEquivalent: "r")
        fileMenu.addItem(withTitle: "Delete", action: #selector(MainWindowController.deleteSelected(_:)), keyEquivalent: "\u{8}")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Refresh", action: #selector(MainWindowController.refresh(_:)), keyEquivalent: "e")

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Focus Left Pane", action: #selector(MainWindowController.focusLeftPane(_:)), keyEquivalent: "1")
        viewMenu.addItem(withTitle: "Focus Right Pane", action: #selector(MainWindowController.focusRightPane(_:)), keyEquivalent: "2")
    }
}
