import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) { HotKeys.reload()
    }
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool { showSettings(); return true }
}

var settingsWindow: NSWindow?

func showSettings() {
    if settingsWindow == nil {
        let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().frame(width: 440, height: 720)))
        w.title = "FastShot Settings"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        settingsWindow = w
    }
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
}

@main
struct FastShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var rec = Recorder.shared

    var body: some Scene {
        MenuBarExtra {
            Button("Region screenshot") { pickRegion() }
            Button("Full-screen screenshot") { capture(rect: nil) }
            Button(rec.isRecording ? "Stop recording" : "Start recording") { rec.toggle() }
            Divider()
            Button("Settings…") { showSettings() }
            Button("Quit") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: rec.isRecording ? "record.circle.fill" : "camera.viewfinder")
        }
    }
}

struct HotKeyField: View {
    let a: Action
    @AppStorage private var code: Int
    @AppStorage private var mods: Int
    @AppStorage private var label: String
    @State private var listening = false
    @State private var monitor: Any?

    init(_ a: Action) {
        self.a = a
        _code = AppStorage(wrappedValue: a.code, a.key + ".code")
        _mods = AppStorage(wrappedValue: a.mods, a.key + ".mods")
        _label = AppStorage(wrappedValue: a.label, a.key + ".label")
    }

    var body: some View {
        LabeledContent(a.title) {
            Button(listening ? "Press keys…" : label) { listen() }.frame(minWidth: 90)
        }
    }

    func listen() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        listening = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            defer { listening = false; if let m = monitor { NSEvent.removeMonitor(m); monitor = nil } }
            if e.keyCode == 53 { return nil }
            let f = e.modifierFlags.intersection([.command, .shift, .option, .control])
            guard !f.isEmpty else { NSSound.beep(); return nil }
            code = Int(e.keyCode); mods = carbonMods(f)
            label = (f.contains(.control) ? "⌃" : "") + (f.contains(.option) ? "⌥" : "") + (f.contains(.shift) ? "⇧" : "") + (f.contains(.command) ? "⌘" : "") + (e.charactersIgnoringModifiers ?? "?").uppercased()
            HotKeys.reload()
            return nil
        }
    }
}

struct SettingsView: View {
    @AppStorage("recFps") var fps = 60
    @AppStorage("recRes") var res = 1080
    @AppStorage("recSys") var sys = true
    @AppStorage("recMic") var mic = false
    @AppStorage("hudScale") var hudScale = 1.0
    @AppStorage("hudY") var hudY = 0.3
    @AppStorage("hudWidth") var hudWidth = 1.0
    @AppStorage("hudStyle") var hudStyle = "glass"
    @AppStorage("hudCapture") var hudCapture = false
    @State var preview = false

    func refreshPreview() {
        if preview { DispatchQueue.main.async { showHUD("checkmark.circle.fill", "Copied screenshot", sticky: true) } } else { hideHUD() }
    }
    @State var granted = CGPreflightScreenCaptureAccess()
    @State var login = SMAppService.mainApp.status == .enabled
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Hotkeys (click, then press new combo)") {
                ForEach(actions, id: \.key) { HotKeyField($0) }
            }
            Section("Quick recording") {
                Picker("Frame rate", selection: $fps) {
                    ForEach([24, 30, 60, 120], id: \.self) { Text("\($0) fps").tag($0) }
                }
                Picker("Resolution", selection: $res) {
                    Text("720p").tag(720); Text("1080p").tag(1080); Text("1440p").tag(1440); Text("Native").tag(0)
                }
                Toggle("System audio", isOn: $sys)
                Toggle("Microphone (macOS 15+, saved as 2nd audio track)", isOn: $mic)
                Text("Saved to Desktop as .mp4; file is also copied to the clipboard. Never upscales past the display.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Popup") {
                LabeledContent("Size") { Slider(value: $hudScale, in: 0.6...2) }
                LabeledContent("Width") { Slider(value: $hudWidth, in: 1...3) }
                LabeledContent("Height") { Slider(value: $hudY, in: 0.05...0.95) }
                Picker("Style", selection: $hudStyle) {
                    Text("Liquid Glass").tag("glass"); Text("Metamod").tag("metamod"); Text("Solus UI v2").tag("solus")
                }
                Toggle("Visible in screenshots / recordings", isOn: $hudCapture)
                Toggle("Preview (stays on screen)", isOn: $preview)
                    .onChange(of: preview) { _, _ in refreshPreview() }
                    .onChange(of: hudScale) { _, _ in refreshPreview() }
                    .onChange(of: hudY) { _, _ in refreshPreview() }
                    .onChange(of: hudWidth) { _, _ in refreshPreview() }
                    .onChange(of: hudStyle) { _, _ in refreshPreview() }
                    .onChange(of: hudCapture) { _, _ in refreshPreview() }
                    .onDisappear { hideHUD() }
            }
            Section("System") {
                LabeledContent("Screen Recording") {
                    HStack {
                        Text(granted ? "Granted ✓" : "Not granted").foregroundStyle(granted ? .green : .red)
                        if !granted {
                            Button("Request") { CGRequestScreenCaptureAccess() }
                            Button("Open Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
                        }
                    }
                }
                Toggle("Launch at login", isOn: $login).onChange(of: login) { _, on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { log("login item: \(error)") }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in granted = CGPreflightScreenCaptureAccess() }
    }
}
