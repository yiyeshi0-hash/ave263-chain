# 26.3 AppleJPEGDriver mul 回绕 — 真机验证结论（2026-08-17）

## 目标
验证 26.3 (iPad11,6 / 23D127) 内核 AppleJPEGDriver 的
getMCUSize 32 位乘法回绕链（与 AVE CalcBufSizeOfCodedData 同构）能否触发。

## 静态结论（早前）
- getMCUSize (0xfffffff00901ac70): `mul w8, w8, w9` 32 位乘法，
  cols=ceil(w/8), rows=ceil(h/8)，w×h ≥ 2^38 时回绕（w,h ≥ 0x80000=524288）
- 调用者：startEncoder (0x901bc4c，无宽高检查) / startEncoderExt (0x901c008，≤0x10000) / startEncoder2024 (0x901c988，≤0x10000)
- 用户态入口：AppleJPEGDriverUserClient（IOUserClientEntitlements 检查 iokit-user-client-class → 未越狱被挡）
- 触发面：系统进程 VideoToolbox JPEG 编码（普通 app 可用公共 API）

## 真机实验（26.3 iPad 8，iloader-autosign 签名安装）
App 用 VideoToolbox VTCompressionSessionCreate(kCMVideoCodecType_JPEG) + EncodeFrame 逐尺寸测试。

### 结果
| session 尺寸 | create | encode | OUT |
|---|---|---|---|
| 16384² (0x4000) | OK | OK | status=0, out=16384² |
| 32768² (0x8000) | OK | **-6662** | 失败 |
| 65536² ~ 4194304² | OK | **-6662** | 失败 |

### 判定
1. **VideoToolbox 用户态对 JPEG session 尺寸无限制**（4194304² create 也 OK）
2. **编码阶段存在 0x8000 (32768²) 尺寸上限**（-6662 = 编码器错误）
3. **-6662 从 32768² 开始，远早于回绕点 524288²**（32768² 的 MCU 乘积 4096×4096=16M 不回绕）
   → **-6662 是尺寸限制，不是 mul 回绕表现**
4. **mul 回绕需要 ≥524288² 的真实编码，被 0x8000 上限拦截 → 26.3 不可触发**

## 结论
候选 #1（getMCUSize mul 回绕）在 26.3 上**不可利用**：
- 编码路径 0x8000 上限拦截大尺寸
- create 阶段虽然接受 524288²（可能触发回绕），但回绕的 MCU 总数无下游使用（编码被拒）
- 无 OOB 写路径可达

## A11 (iOS 17.0, 20H380) 交叉验证（2026-08-17 追加）
用同样方法（VTCompressionSessionCreate + 4096² 帧 encode）在 A11 越狱机验证：
- create 全部尺寸 OK（含 1048576²）
- **encode 同样从 32768² 起返回 -6662**（与 26.3 完全一致）
- **结论：JPEG 编码的 0x8000 (32768²) 上限是两个固件的通用硬件限制**
- mul 回绕需 w×h≥2^38（每边 ≥0x80000=524288），远超编码上限（≤2^30 面积 / ≤32768 每边）
- **mul 回绕在 JPEG 编码路径彻底不可触发（两个固件）**

## 环境资产（已建成，后续复用）
- 黑苹果 (192.168.3.128, zhou/123456)：Xcode 26.3 + brew(ipsw/ldid/xcodegen) + 26.3 iPad USB
- 26.3 iPad 8 (iPad11,6, 23D127)：iloader-autosign (Windows) 签名安装链路可用
- pymobiledevice3 (Windows)：apps install/pull/launch/crash 全链路
- JPEG 测试 app 工程：~/Projects/AVE263 (Mac) / D:\dsh-work\tools\ipa_src (Win)

## 备注
- ImageIO (CGImageDestination) 路径：CGImageCreate 因 dummy provider 数据不足全尺寸失败，未走通
- 候选 #2（setup 地址偏移 mul）同样受 encode/decode 路径限制
- **下一步：A11 (iOS 17.0, 20H380) 老驱动验证**——A11 可能无 0x8000 上限，
  且越狱机可直接 IOKit 调 startEncoder（注入 entitlement），若成立则 mul 回绕闭环可验证
