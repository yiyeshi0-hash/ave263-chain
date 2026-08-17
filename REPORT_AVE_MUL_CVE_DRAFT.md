# AppleAVE2Driver 32-bit Multiply Overflow → Kernel Heap Overflow
## 漏洞报告草稿（26.3 iPadOS，CVE-2026-64747 同族）

## 1. 概述
**组件**: AppleAVE2Driver（iOS 内核视频硬件编码驱动，A11/A12+ 芯片）
**类型**: 32-bit integer overflow → undersized kernel buffer → OOB write
**影响**: 内核堆 OOB 写（潜在 LPE/RCE，需本地代码执行或特定 entitlement）
**受影响**: iPadOS 26.3 (23D127)（26.6 已修复）

## 2. 根因
`AppleAVE2Driver::CalcBufSizeOfCodedData` 内 32 位乘法：
```asm
mul w8, w9, w10      ; width × height (32-bit, no overflow check)
```
用户可控的 32 位 width/height 乘积 ≥ 2^32 时回绕，
`bufSize` 变成小值 → 内核分配过小 buffer → 编码器写入越界。

**26.6 修复**: 新增 17 个 `AVE_CalcBufSizeOf*` 检查函数，模式：
```asm
smull x8, w9, w10    ; 64-bit multiply
tbnz  x8, #0x1f, err ; high bit set -> error
cmp   w8, #0x80000000
b.hi  err
```

## 3. 触发链（26.3）
```
用户态: AppleAVE2DriverUserClient IO_Start (sel 4, structIn=236656)
  IOStruct +0x10cfc = width  (32-bit, user-controlled)
  IOStruct +0x10d00 = height (32-bit, user-controlled)
        ↓
内核: CalcBufSizeOfCodedData(width, height)
  mul w8, w9, w10    ← 65536×65536 = 2^32 → 回绕为 0
  bufSize = 0/小值 → 过小分配 → OOB 写
```

## 4. 触发面分析（实测）
| 路径 | 26.3 结果 |
|---|---|
| VideoToolbox VTCompressionSessionCreate+EncodeFrame | **-19354 于 16384²**（VideoToolbox 用户态尺寸上限，无法传 65536²） |
| 直接 IOKit IO_Start (65536²) | 需 `iokit-user-client-class: AppleAVE2UserClient` entitlement（未越狱拒绝） |
| 越狱后直接 IOKit | **可触发**（entitlement 注入，A11 越狱机验证 IO_Start 调用链） |

**限制**: 未越狱设备上 VideoToolbox 用户态限制 session 尺寸（-19354 @16384²），
直接 IOKit 需要 Apple 私有 entitlement → **攻击者需本地代码执行（越狱/恶意 app+entitlement）**

## 5. 影响
- 内核堆 OOB 写（bufSize 回绕 → 过小分配 → 编码器 DMA/写越界）
- 越狱提权链（从越狱用户态到内核）
- 潜在沙箱逃逸（若系统进程可控尺寸）

## 6. 调用链真值（A11 越狱机 frida 抓取，26.3 应同构）
```
IOServiceOpen type=1 → AppleAVE2DriverUserClient
IO_Open    sel 0, in=1232
IO_Prepare sel 3, in=236656   (+0x10cfc=w, +0x10d00=h)
IO_Start   sel 4, in=236656   (+0x10cfc=w, +0x10d00=h)
IO_Command sel 7, in=32
IO_Complete sel 6, in=24
```

## 7. 证据
- 26.3 静态：CalcBufSizeOfCodedData `mul w8,w9,w10` 无检查
- 26.6 修复：17 个检查函数（smull+tbnz #0x1f + cmp 0x80000000）
- A11 篡改验证：IO_Start 宽高改 65537²/0xFFFFFFFF² → kr=0（接受大宽高，无检查拦截）
  （A11 iOS17 驱动与 26.3 编码路径不同，崩溃闭环未在 A11 复现）

## 待办
- [ ] 26.3 越狱环境（当前无公开越狱）验证崩溃闭环
- [ ] 确认 26.3 的 IO_Start 结构与 A11 偏移一致性（需 26.3 内核）
