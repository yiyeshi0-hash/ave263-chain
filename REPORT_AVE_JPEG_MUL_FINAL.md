# AVE/JPEG mul 溢出触发面 — 完整验证结论（2026-08-17）

## 背景
26.3 (iPad11,6 / 23D127) 内核两个 32 位乘法回绕候选：
- **AVE** (AppleAVE2Driver): CalcBufSizeOfCodedData `mul wX,wY` w×h，26.6 已修复（smull+tbnz）
- **JPEG** (AppleJPEGDriver): getMCUSize `mul w8,w8,w9` cols×rows，未修复

## 验证链

### 1. JPEG mul 回绕 — 不可利用 ❌
- 26.3 与 A11 真机（VideoToolbox create+encode）：
  - create 任意尺寸 OK（含 4194304²）→ startEncoder/getMCUSize 可达
  - **encode 从 32768² (0x8000) 起全部 -6662**（硬件编码上限，两固件一致）
- 回绕需 w,h ≥ 524288² → 被 0x8000 上限拦截 → **mul 回绕不可触发**

### 2. AVE mul 溢出 — 触发面受限 ⚠️
- 26.3 真机（VideoToolbox H264）：
  - create 任意尺寸 OK
  - **encode 从 16384² 起 -19354**（VideoToolbox 层尺寸拒绝）
  - mul 溢出需 w×h ≥ 2^32（65536² 精确回绕）→ 被 16384² 上限拦截
- 26.3 直接 IOKit：iokit-user-client-class entitlement 挡（未越狱）
- A11 越狱机直接 IOKit（frida 篡改 mediaserverd 的 IO_Start 宽高）：
  - 抓到 VideoToolbox 真实 AVE 调用：IO_Open(sel0,in=1232) / IO_Prepare(sel3,in=236656) / IO_Start(sel4,in=236656)
  - **宽高偏移确认：IO_Start +0x10cfc (w) / +0x10d00 (h)**
  - **篡改 65537² 和 0xFFFFFFFF² → kr=0，无崩溃**（A11 iOS17 驱动与 26.3 不同构，无同款 mul 路径）

## 最终判定
| 漏洞 | 26.3 静态 | 26.3 真机触发 | 可利用性 |
|---|---|---|---|
| AVE mul 溢出 (26.6 修复) | 确认存在 | VideoToolbox 层 16384² 上限拦截；直接 IOKit 需 entitlement | **需越狱/entitlement，未验证闭环** |
| JPEG mul 回绕 | 确认存在 | 0x8000 编码上限拦截 | **不可利用** |

## 关键事实（报告用）
1. **26.3 VideoToolbox 用户态对 session 尺寸无限制**（create 接受任意尺寸），限制在**编码阶段**（AVE: -19354 @16384², JPEG: -6662 @32768²）
2. **AVE 调用链真值**（A11 抓取，26.3 应同构）：IO_Open in=1232, IO_Prepare/IO_Start in=236656, 宽高 @+0x10cfc/+0x10d00
3. **26.3 AVE mul 的触发条件**：需绕过 VideoToolbox 用户态尺寸检查（直接 IOKit + entitlement，或越狱后篡改）
4. **环境资产**：黑苹果 Xcode26.3 本地构建 + iloader 签名安装 + pymobiledevice3 自动化全链路可用

## 建议
- AVE mul 溢出（26.6 修复）按"需本地代码执行/entitlement"级别提交
- 或继续扫描 26.3 其他驱动（IOAESAccelerator/AppleKeyStore/IOReport/IOSurfaceRoot）找无限制入口
