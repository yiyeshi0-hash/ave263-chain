// AVERunnerV2.swift — v2: VTCompressionSession (强化版, 调用 AVERunner.startV2)
// 主要触发路径: 65537x65537 编码会话 → AppleAVE2 CalcBufSize mul 溢出
import Foundation

final class AVERunnerV2 {
    static let shared = AVERunnerV2()
    private init() {}

    func start(_ report: @escaping (String) -> Void) {
        AVERunner.shared.startV2(report)
    }
}
