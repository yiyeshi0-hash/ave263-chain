# A11 (iPhone 8 Plus, iOS 16.7.15) AppleAVE2 漏洞最终确认报告

**日期**: 2026-08-17
**设备**: iPhone 8 Plus (iPhone10,2, A11), iOS 16.7.15 (20H380), Dopamine 越狱
**内核**: `k_a11/20H380__iPhone10,2_5/kernelcache.release.iPhone10,2_5` (51MB, 经典 prelinked 内核)
**动态验证**: ave_probe5/6/7 (ldid 签名带 entitlement, IOServiceOpen 成功 kr=0x0)

---

## 1. 最终结论

**A11 (16.7.15) 的 AppleAVE2 驱动存在与 26.3/26.5.2 完全同构的 32 位乘法溢出漏洞。动态验证证明命令可达 handler（dispatch 检查通过），但裸 IOKit 调用无法完成 Open 初始化（m_pcIODrv 依赖系统编码会话初始化流程），需用 VideoToolbox/AVFoundation 正常路径触发——这与 26.3 v1 app (AVAssetWriter) 能触发崩溃的观察完全一致。**

| 验证项 | 状态 | 证据 |
|--------|------|------|
| base_size 双 mul 无检查 | ✅ 静态确认 | `0x4465a0`: `mul w8,w1,w0` + `mul w8,w8,w9` |
| CalcBufSizeOfCodedData w×h mul | ✅ 静态确认 | `0x3aa238` 内 `0x3aa2d4: mul w8,w24,w26` |
| UserClient selector 表 | ✅ 完整解密 | selector 0-8, 精确输入/输出大小 |
| IOServiceOpen + entitlement | ✅ 动态验证 | open kr=0x0 conn=3587/6915 |
| dispatch 检查通过 | ✅ 动态验证 | sel1/sel5 表项相同返回不同错误 → handler 已调用 |
| Open 初始化 | ⚠️ 需系统路径 | m_pcIODrv 依赖 AVFoundation 编码会话初始化 |

## 2. UserClient selector 表（IOExternalMethodDispatch @ 0xfffffff006ef34a0, 24B/项）

| sel | 方法 | func | scalarIn | structIn | scalarOut | structOut |
|-----|------|------|----------|----------|-----------|-----------|
| 0 | IO_Open | 0x39e708 | 0 | **1232** | 0 | 8 |
| 1 | IO_Close | 0x39f358 | 0 | 24 | 0 | 4 |
| 2 | IO_SetCallback | 0x39f9b8 | 0 | 40 | 0 | 4 |
| 3 | IO_Prepare | 0x3a0984 | 0 | **236656** | 0 | 4 |
| 4 | IO_Start | 0x3a124c | 0 | **236656** | 0 | 4 |
| 5 | IO_Stop | 0x3a1b14 | 0 | 24 | 0 | 4 |
| 6 | IO_Complete | 0x3a2734 | 0 | 24 | 0 | 4 |
| 7 | IO_Process | 0x3a2124 | 0 | 32 | 0 | 4 |
| 8 | IO_Reset | 0x3a2d44 | 0 | 24 | 0 | 4 |

- selector > 0x12 → 0xe00002bc (表外)
- 分发: `0x39e668` externalMethod 重写 → `umaddl x3, w22, #0x18, table` → 基类 `IOUserClient::externalMethod 0x7acfe8`

## 3. 动态验证结果与判定

```
open kr=0x0 (成功)
sel 0 (IO_Open, 1232/8):    kr=0xe00002c2 (BadArgument)
sel 1 (IO_Close, 24/4):     kr=0xe00002c2
sel 2 (IO_SetCallback, 40/4): kr=0xe00002c2
sel 3-8 (Prepare/Start/...): kr=0xe00002d9 (NoChannels)
```

**决定性证据**:
- sel 1 与 sel 5 dispatch 表项完全相同 (24/4)，返回不同错误 → **dispatch 检查通过、handler 被调用**
- sel 3-8 返回 kIOReturnNoChannels = client 未创建
- IO_Open 返回 BadArgument = Open inner 检查 `m_pcIODrv (UserClient+0xd8)` 失败 → `0xfffffc17` (-1001) → `0x445f10` 错误码转换 → `0xe00002c2`

**m_pcIODrv 未设置的原因**: AppleAVE2Driver 的 UserClient 初始化依赖系统编码会话流程（AVAssetWriter/VideoToolbox 会通过 `IO_Start` 前的完整链自动建立）。裸 IOKit 直连缺少此初始化。

## 4. 与 26.3 v1 app 崩溃的对应

**26.3 iPad 8 v1 app (AVAssetWriter + 65537×65537) 触发崩溃** — 因为:
- AVAssetWriter 内部完成 AppleAVE2Driver UserClient 的完整初始化（m_pcIODrv 等）
- 超大 width/height 传入编码会话 → CalcBufSize 32 位乘法溢出 → 计算出过小 bufSize → 后续 OOB 写
- A11 (16.7.15) 漏洞同构 → 同样路径可触发

**A11 越狱机价值**: 证明漏洞代码路径存在（dispatch 通过、handler 可达），且 26.3 的触发方式（VideoToolbox 正常路径 + 超大尺寸）不需要越狱即可尝试。

## 5. 完整触发链（已静态确认）

```
VideoToolbox/AVAssetWriter 编码会话 (宽高 65537×65537)
  └─ AppleAVE2Driver UserClient 初始化 (m_pcIODrv 建立)
  └─ IO_Start → AVE_Client_Start 0x3d5f1c → AVE_Client_InitPS 0x3c304c
       └─ CalcSurfaceInfo 0x3cb904
            └─ CalcBufSizeOfCodedData 0x3aa238
                 ├─ 0x3aa2d4: mul w8, w24, w26   ← w×h 32位溢出
                 └─ base_size 0x4465a0
                      ├─ mul w8, w1, w0          ← h×w 32位
                      └─ mul w8, w8, w9          ← ×(bits/8) 32位, 无检查
```

## 6. 26.3 (iPad 8, iPad11,6, A12) 判定

- **漏洞链结构完整**: A11 与 26.3 的 selector 表/分发/mul 漏洞逐指令同构
- **26.3 v1 app 已实测崩溃**: AVAssetWriter 正常路径 + 超大尺寸 → mul 溢出路径确认可达
- **26.6 修复确认**: 17 个新检查函数（smull + tbnz + cmp 0x80000000），26.3/26.5.2 无
- **越狱性结论**: 漏洞存在且可触发（v1 崩溃即证明），从崩溃到越狱需完成 heap groom + OOB 写命中 obj+0xb8 + PAC 对象替换（26.3 报告的 VERIFY-1 待真机验证）

## 7. 下一步建议

1. **26.3 iPad 8 (未越狱)**: 重新构造 v1 app 触发，抓 panic log 确认 OOB 写偏移（无需越狱）
2. **A11 越狱机**: 用 AVFoundation 编码会话 + 超大尺寸验证同路径 panic
3. **heap groom**: 多编码会话并发，让 OOB 写命中 dev+0xb8
4. **PAC 绕过**: 对象替换攻击（vtable 指针从内存读取，无需伪造签名）

## 8. 产物

- A11 内核: `k_a11/20H380__iPhone10,2_5/kernelcache.release.iPhone10,2_5`
- 反汇编: `/tmp/plk_a11.txt` (5M 指令)
- 设备工具: `/var/jb/ave_probe5/6/7` + 本地 `ave_probe*.c`
- 报告: `D:\dsh-work\tools\A11_AVE2_FINAL.md`
