import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut: a virtual key code plus a Carbon modifier mask.
struct KeyCombo {
    let keyCode: UInt32
    let modifiers: UInt32

    /// - Parameters:
    ///   - keyCode: a `kVK_ANSI_*` virtual key code.
    ///   - modifiers: an OR of Carbon modifier flags (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    init(_ keyCode: Int, _ modifiers: Int) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
    }
}

/// Registers global (system-wide) hotkeys via the Carbon HotKey API and dispatches each
/// press to a `Command`'s `run` closure.
///
/// Carbon's `RegisterEventHotKey` is used deliberately: it is the only mechanism that
/// registers an app-scoped global hotkey WITHOUT requiring Accessibility / Input Monitoring
/// permission, and it consumes the keystroke so it does not leak to the frontmost app. The
/// HotKey subset of Carbon remains supported on modern macOS even though Carbon as a whole is
/// deprecated — do not "modernize" this away without a replacement that keeps the
/// no-permission property (e.g. NSEvent global monitors would force a TCC prompt and cannot
/// consume the event).
final class HotKeyCenter {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handlerRef: EventHandlerRef?

    /// Four-char signature ('WTN!') tagging this app's hotkeys.
    private static let signature: OSType = 0x5754_4E21

    /// Registers every command that carries a `key`. Safe to call once at startup.
    func register(_ commands: [Command]) {
        installHandlerIfNeeded()
        for command in commands {
            guard let combo = command.key else { continue }
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: HotKeyCenter.signature, id: command.id)
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            if status != noErr {
                NSLog("WatsonStatus: could not register hotkey for \"\(command.title)\" "
                    + "(OSStatus \(status)) — it may already be claimed by another app.")
                continue
            }
            // Only record the action once the OS registration succeeded, so a rejected combo
            // does not leave a dead entry that nothing can ever dispatch.
            actions[command.id] = command.run
            hotKeyRefs.append(ref)
        }
    }

    deinit {
        for case let ref? in hotKeyRefs { UnregisterEventHotKey(ref) }
        if let handlerRef = handlerRef { RemoveEventHandler(handlerRef) }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(event,
                                        EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        nil,
                                        MemoryLayout<EventHotKeyID>.size,
                                        nil,
                                        &hotKeyID)
            guard err == noErr else { return OSStatus(eventNotHandledErr) }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            let action = center.actions[hotKeyID.id]
            // Defer to the next main-run-loop turn so this C handler returns immediately rather
            // than running blocking UI/subprocess work (e.g. NSAlert.runModal, which spins a
            // nested run loop) on the event-dispatch stack and risking re-entrancy.
            DispatchQueue.main.async { action?() }
            return noErr
        }, 1, &spec, context, &handlerRef)
    }
}
