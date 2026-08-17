// AVE263 Runner v2 — direct VideoToolbox path (bypasses AVAssetWriter quirks)
// Uses VTCompressionSession with overflow dims to drive AppleAVE2 size calc.
import AVFoundation
import VideoToolbox

final class AVERunnerV2 {
    static let shared = AVERunnerV2()
    private init() {}

    private let overflowW = 65537
    private let overflowH = 65537

    func start(_ report: @escaping (String) -> Void) {
        report("V2: VTCompressionSession with \(overflowW)x\(overflowH)")

        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(overflowW),
            height: Int32(overflowH),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            sourceImageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        report("VTCompressionSessionCreate status=\(status.rawValue)")
        guard status == noErr, let s = session else {
            report("session create failed — dims likely rejected by VideoToolbox")
            return
        }

        // Configure bitrate etc, then feed a small frame
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: 1_000_000)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime,
                             value: kCFBooleanTrue)

        var pb: CVPixelBuffer?
        let ps = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
                                     kCVPixelFormatType_32BGRA, nil, &pb)
        report("pixel buffer status=\(ps.rawValue)")
        if let p = pb {
            let enc = VTCompressionSessionEncodeFrame(s, imageBuffer: p,
                presentationTimeStamp: CMTime(value: 0, timescale: 600),
                duration: CMTime(value: 1, timescale: 600),
                frameProperties: nil, infoFlagsOut: nil)
            report("encodeFrame status=\(enc.rawValue)")
        }
        VTCompressionSessionInvalidate(s)
        report("V2 done")
    }
}
