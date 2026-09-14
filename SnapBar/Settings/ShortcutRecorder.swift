import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutField: View {
    let title: LocalizedStringKey
    let name: String
    @Binding var combo: KeyCombo?
    @State private var message: String?

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    RecorderView(combo: $combo, message: $message, name: name)
                        .frame(width: 150, height: 24)
                    Button {
                        combo = nil
                        Log.info("shortcut cleared name=\(name)")
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .opacity(combo == nil ? 0 : 1)
                    .help(Text("Clear"))
                }
                if let message {
                    Text(verbatim: message).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}

struct RecorderView: NSViewRepresentable {
    @Binding var combo: KeyCombo?
    @Binding var message: String?
    let name: String

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onRecord = { newCombo in
            combo = newCombo
            message = nil
            Log.info("shortcut recorded name=\(name) combo=\(newCombo.displayString)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                MainActor.assumeIsolated {
                    if HotkeyManager.shared.failedNames.contains(name) {
                        message = String(localized: "Another app already uses this shortcut.")
                    }
                }
            }
        }
        button.onReject = { reason in message = reason }
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.combo = combo
    }
}

/// Click it, press keys, and it becomes the shortcut. Global shortcuts pause while it listens.
final class RecorderButton: NSButton {
    var combo: KeyCombo? { didSet { refreshTitle() } }
    var onRecord: ((KeyCombo) -> Void)?
    var onReject: ((String) -> Void)?
    private var recording = false { didSet { refreshTitle() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggle)
        refreshTitle()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        HotkeyManager.shared.isSuspended = true
        window?.makeFirstResponder(self)
    }

    private func stop() {
        recording = false
        HotkeyManager.shared.isSuspended = false
    }

    override func resignFirstResponder() -> Bool {
        if recording { stop() }
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        handle(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        handle(event)
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stop()
            return
        }
        guard let newCombo = KeyCombo(event: event) else {
            onReject?(String(localized: "Add ⌘, ⌃ or ⌥ to the key."))
            NSSound.beep()
            return
        }
        if newCombo.isReserved {
            onReject?(String(localized: "macOS already uses \(newCombo.displayString)."))
            Log.info("shortcut rejected reserved combo=\(newCombo.displayString)")
            NSSound.beep()
            return
        }
        stop()
        onRecord?(newCombo)
    }

    private func refreshTitle() {
        if recording {
            title = String(localized: "Press keys…")
        } else {
            title = combo?.displayString ?? String(localized: "Record Shortcut")
        }
    }
}
