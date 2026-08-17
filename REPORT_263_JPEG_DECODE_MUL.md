# 26.3 AppleJPEGDriver 解码路径 mul 回绕 → memcpy 越界（新候选，2026-08-17）

## 发现（静态分析，26.3 iPad11,6 kernelcache 23D127）

### 目标函数链
```
AppleJPEGDriver decode 主流程 0xfffffff00901b0f4
  → bl 0xfffffff00901a020  (decode 入口)
      ├─ 校验 [0x328]=期望宽, [0x32c]=期望高 vs [0x37c]=新宽, [0x380]=新高
      │    0x901a180: ldr w8,[x19+0x37c]; cmp w21([0x328]),w8; b.ne → 错误
      │    0x901a18c: ldr w8,[x19+0x32c]; ldr w9,[x19+0x380]; cmp; b.ne → 错误
      │    0x901a1c8: ldrb w8,[x19+0x37c]; tst w8,0xf; b.ne → 错误  (宽16对齐校验)
      │    0x901a1d4: ldrb w8,[x19+0x380]; tst w8,0xf; b.eq → 0x901a474 (跳过分配)
      │    → 不匹配/未对齐 → 0x901a480: bl 0xfffffff0090196a4  (重新分配)
      └─ 0x90196a4(x0=?, x1=session):
           ├─ [0x313]位0=1 → 0x9019bc8: bl 0xfffffff009019bd8
           └─ 0x9019bd8(x1=session):
                mov x19, x1
                ldr w8, [x19+0x37c]   ; 宽 (JPEG 头解析值)
                ldr w9, [x19+0x380]   ; 高
                mul w22, w9, w8       ; ★ 32位乘法回绕
                lsr x24, x22, 1
                x20 = fn(0x9ee6708, arg=0)  ; [x19+0x2c0] 对象方法
                x21 = fn(0x9ee6708, arg=1)
                x23 = x22 + w20       ; 目标偏移 = 面积 + 某值
                x22 = x8' - x23       ; memcpy 长度 = buf_size - 偏移  ← 回绕则长度错误
                if (x22 >= 1) [x19+0x2d0]→vtable[0xd0](x1=x23, x2=0, x3=x22)  ; ★ memcpy 越界
                x21 = x24 + w21
                x20 = x0' - x21
                if (x20 >= 1) [x19+0x2d0]→vtable[0xd0](x1=x21, x2=0, x3=x20)  ; ★ 第二处 memcpy
```

### 漏洞性质
- `mul w22, w9, w8`：32 位宽×高。JPEG 头宽高各 16 位（SOF 段），但 0x37c/0x380
  是 32 位字段，若解码路径允许超 16 位（或经缩放/填充后变大），乘积 ≥ 2^32 回绕。
- 回绕 → x23（偏移）变小、x22（长度）= buf_size - x23 变大 → vtable[0xd0] memcpy
  长度超过缓冲区 → **内核堆越界写**。
- 与已排除的编码路径不同：**此链在解码路径**，宽高来自 JPEG 流（用户/远程可控）。

### 待确认
1. [0x37c]/[0x380] 的实际赋值来源（JPEG SOF 解析函数？宽度 16 位限制是否存在？）
2. [0x313] 位0 的置位条件（哪个模式触发 0x9019bd8）
3. vtable[0xd0] 的具体函数（memcpy？IOBufferMemoryDescriptor 写？）
4. 0x9ee6708/0x9ee65dc 是哪个对象方法（[0x2c0] 指向啥）
5. 26.6/26.5 是否修复（若修复=真 bug 证据）
6. 真机验证路径：VideoToolbox JPEG 解码（恶意 JPEG 头大宽高）+ frida 篡改

### 与既有结论关系
- 之前判定"JPEG mul 不可触发"是基于 **encode** 路径（startEncoder ≤0x8000 上限）。
- 本候选在 **decode** 路径，绕过 encode 上限；decode 的宽高校验（0x901a1c8 16 对齐）
  只查 16 对齐不查上限 → 大宽高可进入分配路径。

### 26.6 对比结论（2026-08-17 补充）
- 26.6 (23G71) JPEG kext (297808B) 同位置函数 0x8d363ec **结构完全一致**：
  `mul w22,w9,w8` + `lsr x24,x22,1` + 两次 `vtable[0xd0]` memcpy，**无新增检查**。
- 字段偏移 26.3 [0x37c]/[0x380] → 26.6 [0x47c]/[0x480]（结构重排，逻辑同构）。
- **26.6 未修复此点** → 不是已修 bug；判定取决于可回绕性（见下）。

### 可回绕性分析（关键）
- JPEG SOF 宽高字段标准 16 位（≤65535）→ 65535² = 0xFFFE0001 < 2^32 **不回绕**。
- 但 0x901ad24（vtable 方法，IOUserClient external method 签名 x0..x4）把用户
  结构 [x1+0x14]（**32 位**宽）与 [x1+0x18]（16 位高）拷入 session 的 0x328 字段。
- 0x901a128 校验 [0x328]==[0x37c] 才走缓存；不相等走 0x90196a4（含 mul）。
- **开放问题**：0x37c 是否也接受 32 位（若 JPEG 头解析用 32 位读）→ 真机验证。

### 真机验证结论（2026-08-17，26.3 iPad 实测）
- 测试方法：PIL 生成合法 8x8 JPEG，patch SOF0 宽高为 65535²/32768²/16384x65536，
  经 CGImageSource（ImageIO）解码。
- **结果：所有 patch 宽高的 JPEG 都被 ImageIO 拒绝**：
  - `props: w=nil h=nil`（ImageIO 无法解析出宽高）
  - `CGImageSourceCreateImageAtIndex FAIL`（拒绝解码）
  - thumbnail 也 FAIL。
- **结论：用户态 ImageIO 对超大 SOF 宽高有校验/拒绝，到不了内核
  AppleJPEGDriver 的 0x9019bd8 mul**。与 encode 路径的 VideoToolbox 上限同理，
  用户态拦截 → 26.3 未越狱不可触发。
- 剩余路径：越狱机 IOKit 直连 startDecoder（绕过 ImageIO）才有机会验证 mul 回绕。
- **候选状态：不可利用（用户态拦截），标记挂起**。
