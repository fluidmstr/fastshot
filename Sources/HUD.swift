import SwiftUI

// Styles: "glass" = Liquid Glass (macOS 26+, blur material before), "metamod" = dark pipe bar.
private struct HUDView: View {
    let icon: String, text: String, style: String
    var scale: CGFloat = 1, box: CGSize? = nil, nat: CGFloat = 0, wmul: CGFloat = 1
    @State private var shown = false
    @State private var n = 0

    // reveals the text from the middle outward: "pied screens" -> "opied screensho" -> full
    var partial: String {
        let c = Array(text), len = min(n, c.count)
        let s = max(0, (c.count - len) / 2)
        return String(c[s..<s + len])
    }

    var animated: some View { Text(text).hidden().overlay(Text(partial).lineLimit(1).fixedSize()) }

    @ViewBuilder var card: some View {
        if style == "solus" {
            let navy = Color(red: 0.08, green: 0.09, blue: 0.2).opacity(0.82)
            let red = Color(red: 0.95, green: 0.25, blue: 0.3)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    Text("fastshot"); Text("|").opacity(0.4)
                    animated
                    Text("|").opacity(0.4); Text(Date.now.formatted(date: .omitted, time: .standard))
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .frame(minWidth: nat * wmul)
                .background(navy, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.12), lineWidth: 1))
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(red)
                    Text(text.split(separator: " ").first.map { $0.uppercased() } ?? "")
                }
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(navy, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(red, lineWidth: 1.5))
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
        } else if style == "metamod" {
            let sep = Text("|").foregroundStyle(.white.opacity(0.35))
            let accent = Color(red: 0.35, green: 0.62, blue: 1)
            HStack(spacing: 8) {
                Text("fast").foregroundStyle(.white) + Text("shot").foregroundStyle(accent)
                sep
                animated.foregroundStyle(.white)
                sep
                Text(Date.now.formatted(date: .omitted, time: .shortened)).foregroundStyle(.white.opacity(0.8))
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(minWidth: nat * wmul)
            .background(Color(red: 0.07, green: 0.08, blue: 0.11).opacity(0.92), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .overlay(alignment: .top) { Rectangle().fill(accent).frame(height: 2).clipShape(RoundedRectangle(cornerRadius: 5)) }
        } else {
            let c = HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold)).symbolEffect(.pulse)
                animated
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.horizontal, 22).padding(.vertical, 14)
            .frame(minWidth: nat * wmul)
            if #available(macOS 26.0, *) {
                c.glassEffect(.regular, in: .rect(cornerRadius: 22))
            } else {
                c.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
            }
        }
    }

    var body: some View {
        card.padding(30)
            .scaleEffect(shown ? 1 : 0.8).opacity(shown ? 1 : 0)
            .scaleEffect(scale)
            .frame(width: box.map { $0.width * scale }, height: box.map { $0.height * scale })
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { shown = true }
                Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { t in
                    n += 1
                    if n >= text.count { t.invalidate() }
                }
            }
    }
}

var hudWindow: NSPanel?

func hideHUD() { DispatchQueue.main.async { hudWindow?.orderOut(nil); hudWindow = nil } }

/// sticky = stays until hideHUD() (settings preview)
func showHUD(_ icon: String, _ text: String, sticky: Bool = false) {
    DispatchQueue.main.async {
        hudWindow?.orderOut(nil)
        let d = UserDefaults.standard
        let scale = d.object(forKey: "hudScale") as? Double ?? 1
        let y = d.object(forKey: "hudY") as? Double ?? 0.3  // fraction of screen height, from bottom
        let style = d.string(forKey: "hudStyle") ?? "glass"
        let wmul = d.object(forKey: "hudWidth") as? Double ?? 1
        let nat = NSHostingView(rootView: HUDView(icon: icon, text: text, style: style)).fittingSize
        let box = CGSize(width: (nat.width - 60) * wmul + 60, height: nat.height)
        let host = NSHostingView(rootView: HUDView(icon: icon, text: text, style: style, scale: scale, box: box, nat: nat.width - 60, wmul: wmul))
        let size = NSSize(width: box.width * scale, height: box.height * scale)
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.level = .statusBar; p.ignoresMouseEvents = true
        p.sharingType = d.bool(forKey: "hudCapture") ? .readOnly : .none
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let f = (NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!).frame
        p.setFrame(NSRect(x: f.midX - size.width / 2, y: f.minY + f.height * y - size.height / 2, width: size.width, height: size.height), display: true)
        p.orderFrontRegardless()
        hudWindow = p
        guard !sticky else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            guard hudWindow === p else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 }) { p.orderOut(nil) }
        }
    }
}
