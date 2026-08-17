# ============================================================================
# iPad 8 (iPad11,6) iPadOS 26.3 (23D127) 越狱工具链 — AVE OOB → 函数插入点
# 逆向依据: AppleAVE2 内核扩展 (26.3 逐字节同构于 26.5.2 漏洞形态)
# 状态: 静态已验证链的 6 个环节; 真机验证项明确标注 [VERIFY-*]
# 警告: 仅限自有设备安全研究
# ============================================================================

## 链总览
# 1. [触发]    用户态 app 打开 AVE 编码会话 (VideoToolbox)
# 2. [溢出]    传超大 width×height → AVE_CalcBufSize 32位乘法溢出 (mul w24,w22,w21)
#             → 计算出过小 bufSize (dev+0x16c) → DPB/块池分配小缓冲
# 3. [OOB写]   编码数据写入时按原始尺寸拷贝 → 内核堆 OOB 写
# 4. [覆盖]    OOB 写覆盖 dev+0xb8 (AVE子设备对象指针) [VERIFY-1 偏移可控性]
# 5. [认证]    PowerOn: ldr x16,[x0](vtable) → autda(0xcda1) → 对象替换攻击过认证
# 6. [执行]    blraa x8,x16 → 调用替换后对象的 vtable+0xb0 虚方法 → 内核代码执行

## 已验证的关键地址 (iPad 26.3 AppleAVE2)
# mul 溢出点:  0xfffffff0089f34f4  (CalcBufSizeOfCodedData 内)
# bufSize 存:  dev+0x16c
# DPB 配置:    sub_fffffff008a5ee7c (读 +0x16c, 仅查负值)
# PowerOn:     sub_fffffff008a6f17c
# 回调数组:    dev+0x100 (4 槽, tbz 循环)
# vtable 调用: 0xfffffff008ab3c84 (obj+0xb8 → [obj]vtable → vtable+0xb0 → blraa, PAC 0xcda1)
# 子设备构造:  sub_fffffff008aac988 (vtable 存 dev+0xb8)
# 设备初始化:  sub_fffffff008a6d1c0 (创建子设备, 触发 PowerOn)

## ================= 工具链代码 =================

### 1. 用户态触发 app (Swift/ObjC) — 编码会话 + 恶意尺寸
# 用 AVAssetWriter + VTCompressionSession 或直接 AVE ioctl。
# 关键参数: width/height 选使 (w*h) 在 32位下溢出的值, 如:
#   w = 0x10001 (65537), h = 0x10001 → 65537^2 = 0x100020001 > 0xFFFFFFFF
#   32位结果 = 0x20001 (131073) — 小正值, 绕过 tbnz #0x1f 负值检查
# [VERIFY-2] 确认 AVE 接受 65537x65537 尺寸 (VideoToolbox 有上限则需别径)

```swift
// TriggerAVE.swift — 需在真机签名运行
import AVFoundation
import VideoToolbox

func triggerOOB() {
    // 恶意尺寸: 32位乘法溢出为小正值
    let w = 65537, h = 65537
    let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: w,
        AVVideoHeightKey: h,
    ]
    // 用 AVAssetWriter 触发编码器创建 (AVE 驱动)
    // [VERIFY-3] 确认此路径到达 AppleAVE2 (A12 的 AVE 驱动)
    // ... 创建 writer + input + startWriting, 写入帧
}
```

### 2. heap groom — 让 OOB 写命中 dev+0xb8
# [VERIFY-1] 核心未知: OOB 写的偏移与 dev 对象的相对位置
# 思路:
#   a. 分配多个编码会话 (多个 dev 对象), 让目标 dev 落在溢出缓冲区之后
#   b. 经典 kalloc 堆喷: 同 size class 对象布局
#   c. OOB 写方向/大小需真机 panic log 确认 (先触发 panic 读崩溃日志)

### 3. PowerOn 触发
# [VERIFY-4] PowerOn 触发点: 编码会话 start / 设备上电 ioctl
# 逆向: sub_a6d1c0 (初始化) → sub_a6f17c (PowerOn), 4 入口
# 候选 ioctl/命令: AVE_CHM_AppendCmd (0xa96818, 70 处调用, 命令 0x11/0x1a)

### 4. 内核代码执行后的原语 (physrw 阶段)
# 获得 vtable 槽方法执行后:
#   a. 用方法参数构造 kernel read/write 原语
#   b. physrw 风格: 物理内存读写 → 定位内核基址 → 绕过 KTRR
#   c. 需要内核基址: 可从 vtable 指针 (已知常数) 推算 slide

## ================= 真机验证清单 =================
# [VERIFY-1] OOB 写偏移可控性 (heap groom) — 最关键, 先做
# [VERIFY-2] AVE 是否接受溢出尺寸 (65537×65537)
# [VERIFY-3] AVAssetWriter 路径是否到达 AppleAVE2
# [VERIFY-4] PowerOn 触发 ioctl
# [VERIFY-5] panic log 确认 OOB 写目标地址 (dev+0xb8 可及性)
# [VERIFY-6] 对象替换候选: 同型子设备对象在堆上可预测存在

## ================= 附: 参考信息 =================
# 26.6 修复对比: 17 个 AVE_CalcBufSizeOf* 检查函数 (26.5.2 仅 1 个无检)
# CVE-2026-64747: AVEVideoEncoder buffer overflow → kernel code exec (26.6 修)
# PAC: DA key, modifier 0xcda1; 对象替换攻击无需伪造
# 报告: REPORT_CHAIN_VERIFICATION.md
