# 26.3 AVE2 解码路径 MB 数计算 mul 回绕（新候选 #2，2026-08-17）

## 发现（26.3 iPad11,6 kernelcache 23D127，AVE2 kext）

### 目标函数 0xfffffff0089e9840（6 参数签名 x0-x5）
```
签名推断：
  w19=x0 (profile/level id)
  w20=x1 (宽度)          ← SPS 解析值
  w21=x2 (高度)          ← SPS 解析值
  w22=x3, w23=x4, w24=x5

关键逻辑：
  cmp w20, w21
  csel w9, w20, w21, gt    ; w9 = max(宽,高) 长边

  movi d0, 0
  asr w10, w20, 4          ; w10 = 宽/16 (MB 列数)
  asr w11, w21, 4          ; w11 = 高/16 (MB 行数)
  mul w10, w11, w10        ; ★★ 32位: (高/16)×(宽/16) = 宏块总数  [回绕点1]
  scvtf d1, w23
  mul w13, w10, w22        ; ★★ 32位: MB总数 × w22            [回绕点2]

  → 查 level 表 0xfffffff007235000+0xdc0（20 项 × 0x24 字节）
     0x8e9a18 循环比较 w13 vs [x12+8], w10 vs [x12+0xc], w9 vs [x12+0x18]
     0x8e9a94: cmp w10, 0x655    ; 0x655=1621 → MB 数上限检查
     0x8e9a9c: cmp w8, 0x13      ; level 索引上限
```

### 漏洞机制
- **回绕点1**：`(w/16)×(h/16)` 用 32 位 mul。若 SPS 宽高 ≥ 2^20（1048576）：
  MB数 = (2^20/16)² = 65536² = 2^32 → **回绕为 0**
- **回绕点2**：`MB总数 × w22` 再回绕
- 回绕后 w10/w13 变小 → **绕过 0x655 (1621) MB 上限检查** → level 表匹配错误
  → 返回错误的 level 限制 → **DPB/参考帧 buffer 分配不足 → 解码 OOB**

### 用户可控性
- w20/w21（宽高）来自 **H.264 SPS**（pic_width_in_mbs_minus1/pic_height_in_map_units_minus1）
  → **远程可控**（恶意视频流）
- 前提：AVE2 解码器接受超大 SPS（用户态 VideoToolbox/CMVideoFormatDescription
  可能拦截——HEVC 之前 -12712；AVC 待实测）

### 26.6 对比（补充）
- 26.6 对应函数 0xfffffe000852c940 区域：**同款裸 mul w 保留**（`add+asr #4` +
  `mul w8,w9,w8`），代码重构为小工具函数但 mul 链未改 → **非已知修复点**。

### 可利用性评估（关键）
- H.264 标准 SPS 宽高上限：pic_width_in_mbs_minus1 16 位 → 最大 65536 像素
  → MB = 4096×4096 = 2^24 < 2^32 → **标准 SPS 不回绕**
- 需非标准 SPS（宽高 32 位）且解码器放行 → 门槛高
- **结论：低优先候选，暂挂起**（除非用户态 AVC 解码实测放行超大 SPS）

### 与既有结论关系
- AVE2 整体用 umull/smull（安全），但**此函数用裸 mul w**——例外点
- 解码路径（SPS 可控）比 encode 路径（VideoToolbox 拦截）更有希望
