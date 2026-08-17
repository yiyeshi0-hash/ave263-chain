// AVERunnerV3.swift — direct IOKit access to AppleAVE2Driver UserClient
// Bypasses VideoToolbox dimension validation. Uses @_silgen_name declarations
// to avoid needing the IOKit Swift module (works on iOS SDK).
import Foundation

// --- IOKit C function declarations (mach/IOKit C API) ---
@_silgen_name("IOServiceGetMatchingService")
private func c_IOServiceGetMatchingService(_ port: mach_port_t, _ dict: UnsafeMutableRawPointer?) -> io_service_t

@_silgen_name("IOServiceMatching")
private func c_IOServiceMatching(_ name: UnsafePointer<CChar>) -> UnsafeMutableRawPointer?

@_silgen_name("IOServiceOpen")
private func c_IOServiceOpen(_ service: io_service_t, _ task: mach_port_t, _ type: UInt32, _ conn: UnsafeMutablePointer<io_connect_t>) -> kern_return_t

@_silgen_name("IOServiceClose")
private func c_IOServiceClose(_ conn: io_connect_t) -> kern_return_t

@_silgen_name("IOConnectCallScalarMethod")
private func c_IOConnectCallScalarMethod(_ conn: io_connect_t, _ sel: UInt32,
    _ inScalar: UnsafePointer<UInt64>?, _ inCount: UInt32,
    _ outScalar: UnsafeMutablePointer<UInt64>?, _ outCount: UnsafeMutablePointer<UInt32>?) -> kern_return_t

@_silgen_name("IOObjectRelease")
private func c_IOObjectRelease(_ obj: UInt32) -> kern_return_t

// --- Types ---
typealias mach_port_t = UInt32
typealias io_service_t = UInt32
typealias io_connect_t = UInt32
typealias kern_return_t = Int32

final class AVERunnerV3 {
    static let shared = AVERunnerV3()
    private init() {}

    func start(_ report: @escaping (String) -> Void) {
        report("V3: direct IOKit AppleAVE2Driver")

        // 1. Find the service
        let matching = c_IOServiceMatching("AppleAVE2Driver")
        guard let m = matching else { report("IOServiceMatching failed"); return }
        let svc = c_IOServiceGetMatchingService(0, m)
        guard svc != 0 else { report("service not found"); return }
        report("service: \(svc)")
        defer { c_IOObjectRelease(svc) }

        // 2. Open the UserClient (type 0 = default)
        var conn: io_connect_t = 0
        let kr = c_IOServiceOpen(svc, 0, 0, &conn)
        report(String(format: "IOServiceOpen kr=0x%08x conn=%u", kr, conn))
        guard kr == 0, conn != 0 else { report("open failed"); return }
        defer { c_IOServiceClose(conn) }

        // 3. Probe selectors 0..15
        for sel in UInt32(0)...UInt32(15) {
            var inScalar: [UInt64] = [0]
            var outScalar = [UInt64](repeating: 0, count: 8)
            var outCount: UInt32 = 8
            let r = inScalar.withUnsafeBufferPointer { inBuf in
                outScalar.withUnsafeMutableBufferPointer { outBuf in
                    c_IOConnectCallScalarMethod(conn, sel,
                        inBuf.baseAddress, UInt32(inBuf.count),
                        outBuf.baseAddress, &outCount)
                }
            }
            let desc: String
            switch r {
            case 0: desc = "OK out=\(outCount) v0=0x\(String(outScalar[0], radix: 16))"
            case 0xe00002c2: desc = "UNSUPPORTED"
            case 0xe00002be: desc = "MIG_BAD_ARG"
            case 0xe00002c1: desc = "MIG_BAD_ID"
            default: desc = String(format: "0x%08x", r)
            }
            report("sel \(sel): \(desc)")
        }
        report("V3 probe done")
    }
}
