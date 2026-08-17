# 26.3 (23D127, iPad11,6/A12) 内核 mul 回绕家族全排查 — 最终报告（2026-08-17）

## 概述
对 26.3 iPad 8 (A12) kernelcache 的驱动层 32 位乘法回绕攻击面做了系统排查。
方法：解包 kernelcache → 提取各驱动 kext → rizin 反汇编 → 定位裸 `mul w`
（32 位乘法）→ 分析操作数来源（用户可控性）→ 真机实测用户态可达性。

## 排查对象与结论

| 驱动 | 裸 mul w 数 | 候选 | 用户态验证 | 结论 |
|------|-----------|------|-----------|------|
| AppleJPEGDriver | 34 | getMCUSize (encode) | VideoToolbox -6662 @32768² 拦截 | ❌ 不可触发 |
| AppleJPEGDriver | 34 | 0x9019bd8 (decode 分配) | ImageIO 拒超大 SOF 宽高 | ❌ 不可触发 |
| AppleAVE2 | 264 | 0x8e99f8 MB 数计算 | 标准 SPS ≤65536 → MB=2²⁴ 不回绕 | ❌ 低优先 |
| AGXG11P | 157 | 无 mul→kalloc 短链 | — | ❌ 无直接候选 |
| AppleH11ANE | 28 | 0x8edc5bc 张量 5×16位维→3×mul32 | CoreML bad_alloc/溢出检查拦截 | ❌ 不可触发 |

## 关键发现（静态）
1. **JPEG decode 新候选 0x9019bd8**：`mul w22=[0x37c]×[0x380]` → 计算
   memcpy 长度 → `[obj+0xd0]` vtable 调用。26.6 (23G71) 同函数 0x8d363ec
   **结构完全一致未修复**。但用户态 ImageIO 拒绝解析超大 SOF 宽高（props=nil），
   到不了驱动。
2. **AVE2 MB 数 mul 0x8e99f8**：`(h/16)×(w/16)×N` 32 位。H.264 标准 SPS
   宽高上限 65536 → MB=2²⁴ < 2³² 不回绕。26.6 同款保留。
3. **ANE 张量 mul 0x8edc5bc**：5 个 16 位维度 → 3 次 32 位连乘 → 元素数。
   数学上必然回绕（65535⁴≫2³²），26.6 H16 同款 0x8a7e6f0 未修复。
   **但 CoreML/MLMultiArray 用户态自带溢出检查**（实测 bad_alloc /
   "integer overflow in multiplication"）→ 到不了驱动。

## 真机实测记录（26.3 iPad, 23D127）
- JPEG decode：PIL 生成合法 JPEG patch SOF 宽高 → CGImageSource 全拒（props=nil）
- ANE：MLMultiArray 超大 shape → std::bad_alloc / overflow 异常
- （历史）JPEG encode：VideoToolbox -6662 @32768²

## 最终判定
**26.3 未越狱状态下，"32 位乘法回绕 → 内核堆 OOB" 家族在用户态可达路径上
全部被拦截**：
- 编码路径：VideoToolbox 尺寸上限
- 解码路径：ImageIO 头校验
- ANE 路径：CoreML 溢出检查
- 唯一例外：越狱后 IOKit 直连（绕过用户态）可触达上述驱动函数——
  但那是"越狱后利用"场景，非远程/沙盒逃逸。

## 产物清单
- `REPORT_263_JPEG_DECODE_MUL.md` — JPEG decode 候选详情
- `REPORT_263_AVE2_MBCOUNT_MUL.md` — AVE2 MB 数候选详情
- `REPORT_263_ANE_TENSOR_MUL.md` — ANE 张量候选详情
- `AVE263-jpegdec.ipa` / `AVE263-ane.ipa` — 真机验证 app
- 26.3/26.6 双内核 JPEG/AVE2/ANE kext 反汇编（/tmp/*.asm）

## 后续可选
1. 越狱机验证（接受前提）：IOKit 直连 JPEG startDecoder / AVE2 / ANE 张量，
   绕过用户态验证 mul 回绕的驱动侧行为
2. 换攻击面：解码器 SPS 解析的其他 bug 型（非 mul）、AGX 命令缓冲解析、
   用户态 installd/WebKit（27b5 已有基础）
