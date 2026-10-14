import Cocoa

var overlays: [NSWindow] = []

func log(_ s: String) {
    fputs("fastshot: \(s)\n", stderr)
    let p = NSHomeDirectory() + "/Library/Logs/FastShot.log"
    if let h = FileHandle(forWritingAtPath: p) ?? { FileManager.default.createFile(atPath: p, contents: nil); return FileHandle(forWritingAtPath: p) }() {
        h.seekToEndOfFile(); h.write(Data("\(Date()) \(s)\n".utf8)); try? h.close()
    }
}

func capture(rect: CGRect?) {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
    let path = NSHomeDirectory() + "/Desktop/Shot \(f.string(from: Date())).png"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    var args = ["-x"]
    if let r = rect { args += ["-R", "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))"] }
    p.arguments = args + [path]
    p.terminationHandler = { t in
        guard let img = NSImage(contentsOfFile: path) else { log("capture failed, status \(t.terminationStatus) (Screen Recording granted?)"); return }
        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([img])
            log("copied \(path)")
            showHUD("checkmark.circle.fill", "Copied screenshot")
        }
    }
    do { try p.run() } catch { log("screencapture: \(error)") }
}

final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class OverlayView: NSView {
    var start: NSPoint?, cur: NSPoint?
    override var acceptsFirstResponder: Bool { true }
    var sel: NSRect? {
        guard let s = start, let c = cur else { return nil }
        return NSRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func cursorUpdate(with e: NSEvent) { NSCursor.crosshair.set() }
    override func mouseMoved(with e: NSEvent) { NSCursor.crosshair.set() }
    override func viewDidMoveToWindow() {
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
        NSCursor.crosshair.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds)
        if let r = sel { path.appendRect(r) }
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        path.fill()
        guard let r = sel else { return }
        NSColor.white.setStroke()
        let b = NSBezierPath(rect: r); b.lineWidth = 1; b.stroke()
        let label = "\(Int(r.width)) × \(Int(r.height))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.7)]
        label.draw(at: NSPoint(x: r.minX, y: max(r.minY - 18, 2)), withAttributes: attrs)
    }

    override func mouseDown(with e: NSEvent) { start = convert(e.locationInWindow, from: nil); cur = start; needsDisplay = true }
    override func mouseDragged(with e: NSEvent) { cur = convert(e.locationInWindow, from: nil); needsDisplay = true }
    override func keyDown(with e: NSEvent) { if e.keyCode == 53 { closeOverlays(nil) } }
    override func mouseUp(with e: NSEvent) {
        guard let r = sel, r.width > 3, r.height > 3, let w = window, let scr = w.screen else { closeOverlays(nil); return }
        // cocoa (bottom-left) -> screencapture global (top-left of main display)
        let mainH = NSScreen.screens[0].frame.height
        let g = CGRect(x: r.minX + scr.frame.minX, y: mainH - (r.maxY + scr.frame.minY), width: r.width, height: r.height)
        closeOverlays(g)
    }
}

func closeOverlays(_ rect: CGRect?) {
    overlays.forEach { $0.orderOut(nil) }
    overlays = []
    guard let r = rect else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { capture(rect: r) }  // let the dim fade out of the frame
}

func pickRegion() {
    guard overlays.isEmpty else { return }
    for s in NSScreen.screens {
        let w = OverlayWindow(contentRect: s.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.level = .screenSaver
        w.becomesKeyOnlyIfNeeded = false
        w.acceptsMouseMovedEvents = true
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let v = OverlayView(frame: NSRect(origin: .zero, size: s.frame.size))
        w.contentView = v
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(v)
        overlays.append(w)
    }
    NSCursor.crosshair.set()
}

