import AppKit

/// The menu bar SnapBar shows while one of its windows is in front.
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(item(String(localized: "About SnapBar"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(item(String(localized: "Settings…"), #selector(AppDelegate.openSettings), ","))
        appMenu.addItem(.separator())
        appMenu.addItem(item(String(localized: "Hide SnapBar"), #selector(NSApplication.hide(_:)), "h"))
        appMenu.addItem(item(String(localized: "Quit SnapBar"), #selector(NSApplication.terminate(_:)), "q"))
        main.addItem(submenu("SnapBar", appMenu))

        let edit = NSMenu(title: String(localized: "menu.edit", defaultValue: "Edit"))
        edit.addItem(item(String(localized: "Undo"), #selector(EditorCanvasView.undo(_:)), "z"))
        edit.addItem(item(String(localized: "Redo"), #selector(EditorCanvasView.redo(_:)), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item(String(localized: "Cut"), #selector(NSText.cut(_:)), "x"))
        edit.addItem(item(String(localized: "Copy"), #selector(NSText.copy(_:)), "c"))
        edit.addItem(item(String(localized: "Paste"), #selector(NSText.paste(_:)), "v"))
        edit.addItem(item(String(localized: "Select All"), #selector(NSText.selectAll(_:)), "a"))
        main.addItem(submenu(String(localized: "menu.edit", defaultValue: "Edit"), edit))

        let file = NSMenu(title: String(localized: "menu.file", defaultValue: "File"))
        file.addItem(item(String(localized: "Save"), #selector(EditorCanvasView.saveDocument(_:)), "s"))
        file.addItem(item(String(localized: "Save As…"), #selector(EditorCanvasView.saveDocumentAs(_:)), "s", [.command, .option]))
        file.addItem(.separator())
        file.addItem(item(String(localized: "Close"), #selector(NSWindow.performClose(_:)), "w"))
        main.insertItem(submenu(String(localized: "menu.file", defaultValue: "File"), file), at: 1)

        let view = NSMenu(title: String(localized: "menu.view", defaultValue: "View"))
        view.addItem(item(String(localized: "Zoom In"), #selector(EditorCanvasView.zoomIn(_:)), "="))
        view.addItem(item(String(localized: "Zoom Out"), #selector(EditorCanvasView.zoomOut(_:)), "-"))
        view.addItem(item(String(localized: "Actual Size"), #selector(EditorCanvasView.zoomActual(_:)), "0"))
        view.addItem(item(String(localized: "Zoom to Fit"), #selector(EditorCanvasView.zoomToFit(_:)), "9"))
        main.addItem(submenu(String(localized: "menu.view", defaultValue: "View"), view))

        let tools = NSMenu(title: String(localized: "menu.tools", defaultValue: "Tools"))
        for (index, tool) in EditorTool.allCases.enumerated() {
            let entry = item(tool.title, #selector(EditorCanvasView.selectTool(_:)), tool.key, [])
            entry.tag = index
            entry.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: nil)
            tools.addItem(entry)
        }
        main.addItem(submenu(String(localized: "menu.tools", defaultValue: "Tools"), tools))

        let window = NSMenu(title: String(localized: "menu.window", defaultValue: "Window"))
        window.addItem(item(String(localized: "Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item(String(localized: "Screenshot Library…"), #selector(AppDelegate.openLibrary)))
        main.addItem(submenu(String(localized: "menu.window", defaultValue: "Window"), window))
        NSApp.windowsMenu = window
        return main
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        return item
    }

    private static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        item.submenu = menu
        return item
    }
}
