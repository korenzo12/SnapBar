import AppKit
import Carbon.HIToolbox

/// Global shortcuts through Carbon's RegisterEventHotKey, which needs no Accessibility permission.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private var names: [UInt32: String] = [:]
    /// Shortcuts macOS refused, usually because another app owns them.
    private(set) var failedNames: Set<String> = []
    /// True while a shortcut recorder is listening, so pressing the old combo records instead of capturing.
    var isSuspended = false {
        didSet { Log.info("hotkeys suspended=\(isSuspended)") }
    }

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if status == noErr {
                let id = hotKeyID.id
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { HotkeyManager.shared.fire(id) }
                }
            }
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &eventHandler)
        Log.info("hotkey handler installed status=\(status)")
    }

    /// Returns false when macOS refuses the combo, usually because another app owns it.
    @discardableResult
    func register(_ combo: KeyCombo, name: String, action: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x534E_4252), id: id)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        Log.info("hotkey registered name=\(name) combo=\(combo.displayString) status=\(status)")
        guard status == noErr, let ref else {
            failedNames.insert(name)
            return false
        }
        failedNames.remove(name)
        refs[id] = ref
        handlers[id] = action
        names[id] = name
        return true
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
        names.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        guard !isSuspended else { return }
        Log.info("hotkey fired name=\(names[id] ?? "?") id=\(id)")
        handlers[id]?()
    }
}

#if DEBUG
extension HotkeyManager {
    /// Runs the same handler the Carbon callback runs, for the registered shortcut called `name`.
    func fireForTest(name: String) {
        guard let id = names.first(where: { $0.value == name })?.key else {
            Log.info("debug hotkey not registered name=\(name)")
            return
        }
        fire(id)
    }
}
#endif
