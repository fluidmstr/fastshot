import AVFoundation
import Cocoa
import ScreenCaptureKit

final class Recorder: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    static let shared = Recorder()
    @Published var isRecording = false

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var sysIn: AVAssetWriterInput?
    private var micIn: AVAssetWriterInput?
    private var started = false
    private var url: URL?
    private var final: URL?
    private let queue = DispatchQueue(label: "fastshot.rec")

    func toggle() {
        if isRecording { Task { await stop() } } else { Task { await start() } }
    }

    private func start() async {
        let d = UserDefaults.standard
        let fps = d.object(forKey: "recFps") as? Int ?? 60
        let res = d.object(forKey: "recRes") as? Int ?? 1080  // 0 = native
        do {
            let content = try await SCShareableContent.current
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
            let did = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
            guard let disp = content.displays.first(where: { $0.displayID == did }) ?? content.displays.first else { log("no display"); return }
            let nw = Int(CGFloat(disp.width) * screen.backingScaleFactor), nh = Int(CGFloat(disp.height) * screen.backingScaleFactor)
            var w = nw, h = nh
            if res > 0 && res < nh { h = res; w = Int(Double(nw) * Double(res) / Double(nh)) }
            w &= ~1; h &= ~1

            let cfg = SCStreamConfiguration()
            cfg.width = w; cfg.height = h
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            cfg.pixelFormat = kCVPixelFormatType_32BGRA
            cfg.showsCursor = true
            cfg.queueDepth = 6
            let wantSys = d.object(forKey: "recSys") as? Bool ?? true
            var wantMic = d.bool(forKey: "recMic")
            cfg.capturesAudio = wantSys
            cfg.excludesCurrentProcessAudio = true
            if #available(macOS 15.0, *), wantMic { cfg.captureMicrophone = true } else { wantMic = false }

            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let name = "Rec \(f.string(from: Date()))"
            final = URL(fileURLWithPath: NSHomeDirectory() + "/Desktop/\(name).mp4")
            let u = URL(fileURLWithPath: NSTemporaryDirectory() + "\(name).raw.mp4")
            try? FileManager.default.removeItem(at: u)
            let wr = try AVAssetWriter(outputURL: u, fileType: .mp4)
            let bitrate = min(max(Int(Double(w * h) * Double(fps) * 0.07), 4_000_000), 120_000_000)
            let inp = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
            ])
            inp.expectsMediaDataInRealTime = true
            wr.add(inp)
            func audioIn() -> AVAssetWriterInput {
                let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000])
                a.expectsMediaDataInRealTime = true
                wr.add(a)
                return a
            }
            sysIn = wantSys ? audioIn() : nil
            micIn = wantMic ? audioIn() : nil
            guard wr.startWriting() else { log("writer: \(String(describing: wr.error))"); return }

            let s = SCStream(filter: SCContentFilter(display: disp, excludingWindows: []), configuration: cfg, delegate: self)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            if wantSys { try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
            if #available(macOS 15.0, *), wantMic { try s.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
            writer = wr; input = inp; url = u; started = false; stream = s
            try await s.startCapture()
            await MainActor.run { isRecording = true }
            NSSound(named: "Pop")?.play()
            showHUD("record.circle.fill", "Recording")
            log("recording \(w)x\(h)@\(fps) -> \(u.path)")
        } catch {
            log("record start failed: \(error) (Screen Recording granted?)")
            if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
            stream = nil; writer = nil
            await MainActor.run { NSSound.beep() }
        }
    }

    private func stop() async {
        guard let s = stream, let wr = writer, let inp = input, let u = url else { return }
        try? await s.stopCapture()
        stream = nil
        await MainActor.run { isRecording = false }
        let had = queue.sync { () -> Bool in
            if started { inp.markAsFinished(); sysIn?.markAsFinished(); micIn?.markAsFinished() }
            return started
        }
        guard had else { wr.cancelWriting(); log("no frames captured"); return }
        await wr.finishWriting()
        let out = final ?? u
        let ff = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
        var ok = false
        if let ff {
            // video copied as-is; system+mic tracks mixed into one so both are audible everywhere
            let hasMix = sysIn != nil && micIn != nil
            var a = ["-y", "-v", "error", "-i", u.path, "-map", "0:v", "-c:v", "copy"]
            if hasMix { a += ["-filter_complex", "[0:a:0][0:a:1]amix=inputs=2:normalize=0[a]", "-map", "[a]", "-c:a", "aac", "-b:a", "192k"] }
            else { a += ["-map", "0:a?", "-c:a", "copy"] }
            a += ["-movflags", "+faststart", out.path]
            let p = Process(); p.executableURL = URL(fileURLWithPath: ff); p.arguments = a
            do { try p.run(); p.waitUntilExit(); ok = p.terminationStatus == 0 } catch { log("ffmpeg: \(error)") }
            if !ok { log("ffmpeg failed, using raw file") }
        } else { log("ffmpeg not found, using raw file") }
        if ok { try? FileManager.default.removeItem(at: u) } else { try? FileManager.default.removeItem(at: out); try? FileManager.default.moveItem(at: u, to: out) }
        NSSound(named: "Glass")?.play()
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([out as NSURL])
        }
        log("saved \(out.path)")
        showHUD("checkmark.circle.fill", "Recording saved")
    }

    func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sb.isValid, let wr = writer, let inp = input else { return }
        if type != .screen {
            guard started, CMSampleBufferGetNumSamples(sb) > 0 else { return }
            var target = type == .audio ? sysIn : nil
            if #available(macOS 15.0, *), type == .microphone { target = micIn }
            if let t = target, t.isReadyForMoreMediaData { t.append(sb) }
            return
        }
        guard let atts = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let st = atts.first?[.status] as? Int, st == SCFrameStatus.complete.rawValue else { return }
        if !started { wr.startSession(atSourceTime: sb.presentationTimeStamp); started = true }
        if inp.isReadyForMoreMediaData { inp.append(sb) }
    }

    func stream(_ s: SCStream, didStopWithError error: Error) {
        log("stream stopped: \(error)")
        Task { if isRecording { await stop() } }
    }
}
