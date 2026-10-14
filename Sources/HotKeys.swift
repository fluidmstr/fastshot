import Carbon.HIToolbox
import Cocoa

// Carbon hotkeys need no Accessibility / Input Monitoring permission.
struct Action { let key: String; let title: String; let code: Int; let mods: Int; let label: String; let run: () -> Void }

let actions: [Action] = [
    Action(key: "region", title: "Region screenshot", code: kVK_ANSI_S, mods: cmdKey | shiftKey, label: "⌘⇧S", run: pickRegion),
    Action(key: "full", title: "Full-screen screenshot", code: kVK_ANSI_R, mods: cmdKey | shiftKey, label: "⌘⇧R", run: { capture(rect: nil) }),
    Action(key: "rec", title: "Quick record start/stop", code: kVK_ANSI_E, mods: cmdKey | shiftKey, label: "⌘⇧E", run: { Recorder.shared.toggle() }),
]

func carbonMods(_ f: NSEvent.ModifierFlags) -> Int {
    var m = 0
    if f.contains(.command) { m |= cmdKey }
    if f.contains(.shift) { m |= shiftKey }
    if f.contains(.option) { m |= optionKey }
    if f.contains(.control) { m |= controlKey }
    return m
}

enum HotKeys {
    static var refs: [EventHotKeyRef] = []
    static var installed = false

    static func reload() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, ev, _ in
                var id = EventHotKeyID()
                GetEventParameter(ev, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                DispatchQueue.main.async { actions[Int(id.id)].run() }
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        let d = UserDefaults.standard
        for (i, a) in actions.enumerated() {
            let code = d.object(forKey: a.key + ".code") as? Int ?? a.code
            let mods = d.object(forKey: a.key + ".mods") as? Int ?? a.mods
            var ref: EventHotKeyRef?
            let st = RegisterEventHotKey(UInt32(code), UInt32(mods), EventHotKeyID(signature: 0x46534854, id: UInt32(i)), GetApplicationEventTarget(), 0, &ref)
            if st == noErr, let r = ref { refs.append(r) } else { log("hotkey \(a.key) register failed: \(st)") }
        }
    }
}
