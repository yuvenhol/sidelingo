import AppKit

@MainActor
public enum ApplicationMenuFactory {
    public static func makeMainMenu(applicationName: String) -> NSMenu {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem(title: applicationName, action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: applicationName)
        applicationMenu.addItem(
            NSMenuItem(
                title: "Quit \(applicationName)",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(command("Undo", selector: "undo:", key: "z"))
        editMenu.addItem(.separator())
        editMenu.addItem(command("Cut", selector: "cut:", key: "x"))
        editMenu.addItem(command("Copy", selector: "copy:", key: "c"))
        editMenu.addItem(command("Paste", selector: "paste:", key: "v"))
        editMenu.addItem(command("Select All", selector: "selectAll:", key: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        return mainMenu
    }

    private static func command(_ title: String, selector: String, key: String) -> NSMenuItem {
        NSMenuItem(title: title, action: Selector((selector)), keyEquivalent: key)
    }
}
