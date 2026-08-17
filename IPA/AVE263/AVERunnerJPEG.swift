// AVERunnerJPEG.swift — 26.3 JPEG encode via VideoToolbox (system path)
// Goal: find whether VT JPEG session create/encode accepts huge dims and
//       whether it reaches kernel startEncoder (unchecked in 26.3) -> getMCUSize mul wrap
import AVFoundation
import VideoToolbox
import UIKit

final class AVERunnerJPEG {
    static let shared = AVERunnerJPEG()
    private init() {}

    private let dims: [(Int32, Int32, String)] = [
        (1920, 1080, "1080p 基线"),
        (8192, 8192, "8192²"),
        (16384, 16384, "16384²"),
        (32768, 32768, "32768²"),
        (65536, 65536, "65536²"),
        (131072, 131072, "131072² 0x20000"),
        (262144, 262144, "262144² 0x40000"),
        (524288, 524288, "524288² 0x80000 回绕点"),
        (1048576, 1048576, "1048576² 0x100000"),
        (4194304, 4194304, "4194304² 0x400000"),
    ]
    private var idx = 0
    private var outLog: (String) -> Void = { _ in }
    private var curSession: VTCompressionSession?
    private var encodeDim: (Int32, Int32) = (0, 0)

    private let outputCallback: VTCompressionOutputCallback = { refcon, _, status, flags, sampleBuffer in
        guard let ref = refcon else { return }
        let runner = Unmanaged<AVERunnerJPEG>.fromOpaque(ref).takeUnretainedValue()
        var msg = "OUT status=\(status)"
        if let sb = sampleBuffer, let desc = CMSampleBufferGetFormatDescription(sb) {
            let d = CMVideoFormatDescriptionGetDimensions(desc)
            msg += " out=\(d.width)x\(d.height)"
        }
        runner.outLog(msg)
    }

    func next() -> String {
        idx = (idx + 1) % dims.count
        return "next JPEG = \(dims[idx].2)"
    }

    // create-only mode: does VT accept huge JPEG session dims?
    func createOnly(_ report: @escaping (String) -> Void) {
        let (w, h, tag) = dims[idx]
        report("=== JPEG create-only [\(idx)] \(tag) \(w)x\(h) ===")
        outLog = report
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: w, height: h,
            codecType: kCMVideoCodecType_JPEG,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: outputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session)
        report("create=\(status) \(status == noErr ? "OK" : "REJECT")")
        if let s = session {
            // try property readback
            var wv: CFTypeRef?
            VTSessionCopyProperty(s, key: kVTCompressionPropertyKey_EncoderID, allocator: nil, valueOut: &wv)
            if let enc = wv { report("encoderID=\(enc)") }
            curSession = s
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
                if let s2 = self?.curSession { VTCompressionSessionInvalidate(s2); self?.curSession = nil }
                report("invalidated")
            }
        }
    }

    // create + encode one small frame: reaches encode path?
    func createAndEncode(_ report: @escaping (String) -> Void) {
        let (w, h, tag) = dims[idx]
        report("=== JPEG create+encode [\(idx)] \(tag) \(w)x\(h) ===")
        outLog = report
        encodeDim = (w, h)
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: w, height: h,
            codecType: kCMVideoCodecType_JPEG,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: outputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session)
        report("create=\(status) \(status == noErr ? "OK" : "REJECT")")
        guard status == noErr, let s = session else { return }
        curSession = s

        // small frame to avoid huge pixel buffers
        var pb: CVPixelBuffer?
        let ps = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &pb)
        report("pb64=\(ps)")
        guard let p = pb else { report("no pb"); return }
        if let base = CVPixelBufferGetBaseAddress(p) {
            memset(base, 0x80, CVPixelBufferGetDataSize(p))
        }
        var flags: VTEncodeInfoFlags = []
        let enc = VTCompressionSessionEncodeFrame(s, imageBuffer: p,
            presentationTimeStamp: CMTime(value: 0, timescale: 600),
            duration: CMTime(value: 1, timescale: 600),
            frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: &flags)
        report("encode64=\(enc) flags=\(flags.rawValue)")

        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
            report("--- complete ---")
            VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
            report("--- done ---")
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                VTCompressionSessionInvalidate(s)
                self.curSession = nil
                report("invalidated")
            }
        }
    }
}
