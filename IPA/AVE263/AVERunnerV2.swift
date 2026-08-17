import AVFoundation
import VideoToolbox

final class AVERunnerV2 {
    static let shared = AVERunnerV2()
    private init() {}

    private let dims: [(Int32, Int32, String)] = [
        (1920, 1080, "1080p正常"),
        (65537, 65537, "65537²(溢出→0x20001)"),
        (65536, 65536, "65536²(不溢出)"),
        (131072, 65538, "131072×65538(溢出→0x40000)"),
    ]
    private var idx = 0

    // 编码输出回调: 记录实际输出的宽高
    private var outLog: (String) -> Void = { _ in }

    private let outputCallback: VTCompressionOutputCallback = { refcon, _, status, flags, sampleBuffer in
        guard let ref = refcon else { return }
        let runner = Unmanaged<AVERunnerV2>.fromOpaque(ref).takeUnretainedValue()
        var msg = "OUTPUT status=\(status)"
        if let sb = sampleBuffer {
            if let desc = CMSampleBufferGetFormatDescription(sb) {
                let dims = CMVideoFormatDescriptionGetDimensions(desc)
                msg += " codedSize=\(dims.width)x\(dims.height)"
            }
        }
        runner.outLog(msg)
    }

    func start(_ report: @escaping (String) -> Void) {
        let (w, h, tag) = dims[idx]
        report("=== v2[\(idx)] \(tag): \(w)x\(h) ===")
        outLog = report

        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: w, height: h,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: outputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session)
        report("create=\(status) \(status == noErr ? "OK" : "REJECT")")
        guard status == noErr, let s = session else { return }

        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_H264_Baseline_AutoLevel)

        var pb: CVPixelBuffer?
        let ps = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
                                     kCVPixelFormatType_32BGRA, nil, &pb)
        report("pb=\(ps) (input frame 64x64)")
        guard let p = pb else { VTCompressionSessionInvalidate(s); report("no pb"); return }

        var flags: VTEncodeInfoFlags = []
        let enc = VTCompressionSessionEncodeFrame(s, imageBuffer: p,
            presentationTimeStamp: CMTime(value: 0, timescale: 600),
            duration: CMTime(value: 1, timescale: 600),
            frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: &flags)
        report("encode=\(enc) flags=\(flags.rawValue)")

        // 等输出回调
        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
            report("--- flush ---")
            VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
            report("--- complete done ---")
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                VTCompressionSessionInvalidate(s)
                report("done")
            }
        }
    }

    func next() -> String {
        idx = (idx + 1) % dims.count
        return "next v2 = \(dims[idx].2)"
    }
}
