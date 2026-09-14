import AppKit
import UniformTypeIdentifiers

/// The actions the panel, the library and notifications share, so each behaves the same everywhere.
@MainActor
enum ShotActions {
    static func copy(_ shots: [Shot]) {
        let urls = shots.map(\.url)
        let ok = urls.count == 1 ? Clipboard.write(fileURL: urls[0]) : Clipboard.write(fileURLs: urls)
        Log.info("action copy count=\(shots.count) ok=\(ok)")
    }

    static func copyPath(_ shots: [Shot]) {
        Clipboard.write(text: shots.map(\.path).joined(separator: "\n"))
        Log.info("action copyPath count=\(shots.count)")
    }

    static func reveal(_ shots: [Shot]) {
        NSWorkspace.shared.activateFileViewerSelecting(shots.map(\.url))
        Log.info("action reveal count=\(shots.count)")
    }

    static func edit(_ shot: Shot) {
        EditorWindowController.open(shot: shot)
        Log.info("action edit id=\(shot.id.uuidString)")
    }

    /// Copies recognized text, running OCR first if the background pass has not finished yet.
    static func copyText(_ shot: Shot) {
        let current = ShotStore.shared.shot(id: shot.id) ?? shot
        if let text = current.ocrText, !text.isEmpty {
            Clipboard.write(text: text)
            Log.info("action copyText chars=\(text.count) cached=true")
            return
        }
        let url = current.url
        let id = current.id
        DispatchQueue.global(qos: .userInitiated).async {
            let text = OCRService.recognizeSync(url: url)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    ShotStore.shared.setOCR(id, text: text)
                    Clipboard.write(text: text)
                    Log.info("action copyText chars=\(text.count) cached=false")
                }
            }
        }
    }

    static func saveAs(_ shot: Shot) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = shot.fileName
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canCreateDirectories = true
        NSApp.activate()
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let ok = copyFile(shot.url, to: dest)
        Log.info("action saveAs ok=\(ok) dest=\(dest.lastPathComponent)")
    }

    /// Copies a file, converting to JPEG when the destination asks for it. Replaces an existing file.
    @discardableResult
    static func copyFile(_ source: URL, to dest: URL) -> Bool {
        try? FileManager.default.removeItem(at: dest)
        let ext = dest.pathExtension.lowercased()
        if (ext == "jpg" || ext == "jpeg"), let image = ImageTools.loadCGImage(url: source) {
            return ImageTools.write(image, to: dest, type: .jpeg, quality: 0.92)
        }
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            return true
        } catch {
            return false
        }
    }

    /// Copies files into `folder` with unique names. Returns the new locations.
    static func exportFiles(_ urls: [URL], to folder: URL) -> [URL] {
        var written: [URL] = []
        for url in urls {
            let dest = FileNaming.uniqueURL(in: folder, fileName: url.lastPathComponent)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil { written.append(dest) }
        }
        return written
    }

    static func export(_ shots: [Shot]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Export")
        NSApp.activate()
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let written = exportFiles(shots.map(\.url), to: folder)
        Log.info("action export count=\(written.count) folder=\(folder.path)")
    }

    /// Moves files to the Trash after one confirmation. Never deletes outright.
    static func trash(_ shots: [Shot], confirm: Bool = true) {
        guard !shots.isEmpty else { return }
        if confirm {
            let alert = NSAlert()
            alert.messageText = shots.count == 1
                ? String(localized: "Move this screenshot to the Trash?")
                : String(localized: "Move \(shots.count) screenshots to the Trash?")
            alert.informativeText = String(localized: "You can restore them from the Trash.")
            alert.addButton(withTitle: String(localized: "Move to Trash"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        ShotStore.shared.remove(ids: Set(shots.map(\.id)), trashFiles: true)
    }

    static func toggleFavorite(_ shots: [Shot]) {
        let makeFavorite = !shots.allSatisfy(\.favorite)
        ShotStore.shared.setFavorite(Set(shots.map(\.id)), makeFavorite)
    }
}
