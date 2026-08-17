// AVERunnerV3.swift — direct IOKit access to AppleAVE2Driver UserClient
// Bypasses VideoToolbox dimension validation. Probes selectors to find the
// encoding-config method, then sends overflow dimensions.
import Foundation
import IOKit

final class AVERunnerV3 {
    static let shared = AVERunnerV3()
    private init() {}

    func start(_ report: @escaping (String) -> Void) {
        report("V3: direct IOKit AppleAVE2Driver")
        // 1. Find the service
        guard let svc = IOServiceGetMatchingService(kIOMainPortDefault,
                     IOServiceMatching("AppleAVE2Driver")) else {
            report("service not found"); return
        }
        report("service: \(svc)")
        defer { IOObjectRelease(svc) }

        // 2. Open the UserClient
        var conn: io_connect_t = 0
        let kr = IOServiceOpen(svc, mach_task_self_, 0, &conn)
        report("IOServiceOpen kr=0x\(String(kr, radix: 16)) conn=\(conn)")
        guard kr == KERN_SUCCESS, conn != 0 else {
            report("open failed"); return
        }
        defer { IOServiceClose(conn) }

        // 3. Probe selectors 0..15 — find which ones return "unsupported"
        //    vs "wrong args". Config methods usually accept struct/scalar input.
        for sel in 0...15 {
            var scalarIn: [UInt64] = [0,0,0,0,0,0,0,0]
            let out = probeSelector(conn, selector: UInt32(sel), report: report)
            report("selector \(sel): \(out)")
        }
    }

    private func probeSelector(_ conn: io_connect_t, selector: UInt32,
                               report: @escaping (String) -> Void) -> String {
        // Try with 1 scalar input first
        var inScalar: [UInt64] = [0]
        var outScalar = [UInt64](repeating: 0, count: 8)
        var outCount: UInt32 = 8
        let kr = IOConnectCallScalarMethod(conn, selector,
                    inScalar, 1, &outScalar, &outCount)
        let code = String(format: "0x%08x", kr)
        switch kr {
        case KERN_SUCCESS: return "OK scalars=\(outCount) first=0x\(String(outScalar[0], radix: 16))"
        case 0xe00002c2: return "UNSUPPORTED selector"
        case 0xe00002be: return "MIG bad arg"
        default: return code
        }
    }
}
