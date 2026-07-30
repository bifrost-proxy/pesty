import AppKit
import Carbon.HIToolbox

@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onTrigger: (() -> Void)?
    var onTranslationTrigger: (() -> Void)?
    var onExplanationTrigger: (() -> Void)?

    private enum HotKeyID: UInt32 {
        case clipboardBar = 1
        case translation = 2
        case explanation = 3
    }

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private var translationRegistrationSuspended = false
    private var explanationRegistrationSuspended = false
    private let signature: OSType = 0x50535459

    private init() {}

    func start() {
        installHandlerIfNeeded()
        reload()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr,
                  hotKeyID.signature == HotKeyCenter.shared.signature else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async {
                HotKeyCenter.shared.handle(id: hotKeyID.id)
            }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    func reload() {
        unregisterAll()
        register(
            id: .clipboardBar,
            keyCode: Settings.shared.hotkeyKeyCode,
            modifiers: Settings.shared.hotkeyModifiers
        )
        if !translationRegistrationSuspended {
            register(
                id: .translation,
                keyCode: Settings.shared.translationHotkeyKeyCode,
                modifiers: Settings.shared.translationHotkeyModifiers
            )
        }
        if !explanationRegistrationSuspended {
            register(
                id: .explanation,
                keyCode: Settings.shared.explanationHotkeyKeyCode,
                modifiers: Settings.shared.explanationHotkeyModifiers
            )
        }
    }

    func suspendTranslationRegistration() {
        translationRegistrationSuspended = true
        unregister(id: .translation)
    }

    func resumeTranslationRegistration() {
        translationRegistrationSuspended = false
        reload()
    }

    func suspendExplanationRegistration() {
        explanationRegistrationSuspended = true
        unregister(id: .explanation)
    }

    func resumeExplanationRegistration() {
        explanationRegistrationSuspended = false
        reload()
    }

    private func register(
        id: HotKeyID,
        keyCode: Int,
        modifiers: Int
    ) {
        guard keyCode >= 0 else { return }
        let eventID = EventHotKeyID(signature: signature, id: id.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            eventID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            hotKeyRefs[id.rawValue] = ref
        } else {
            NSLog(
                "Pesty global hotkey registration failed id=%u status=%d",
                id.rawValue,
                status
            )
        }
    }

    private func unregister(id: HotKeyID) {
        guard let ref = hotKeyRefs.removeValue(forKey: id.rawValue) else {
            return
        }
        UnregisterEventHotKey(ref)
    }

    private func unregisterAll() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    private func handle(id: UInt32) {
        switch HotKeyID(rawValue: id) {
        case .clipboardBar:
            onTrigger?()
        case .translation:
            onTranslationTrigger?()
        case .explanation:
            onExplanationTrigger?()
        case nil:
            break
        }
    }

    static func describe(keyCode: Int, modifiers: Int) -> String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey  != 0 { s += "⌥" }
        if modifiers & shiftKey   != 0 { s += "⇧" }
        if modifiers & cmdKey     != 0 { s += "⌘" }
        s += keyName(for: keyCode)
        return s
    }

    static func keyName(for keyCode: Int) -> String {
        let map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋",
            kVK_ANSI_Period: ".", kVK_ANSI_Comma: ",", kVK_ANSI_Slash: "/"
        ]
        return map[keyCode] ?? "?"
    }
}
