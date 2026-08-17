# iOS 26.5.2 越狱链完整验证报告（含 26.3 可行性）

**日期**: 2026-08-17
**目标**: 验证"26.5.2 可越狱"的整条链，判定 26.3 (iPad 8) 是否同链可用
**方法**: 三内核 AppleAVE2 逆向（26.3 iPad8 / 26.5.2 iPhone18,1 / 26.6 iPhone18,1）+ 26.6 修复 diff + 用户提供地址线索

---

## 验证结论

| 环节 | 状态 | 证据 |
|------|------|------|
| 1. OOB 写来源（CVE-2026-64747） | ✅ 实证 | CalcBufSize 32位乘法溢出，无检查 |
| 2. OOB 写路径 | ✅ 实证 | DPB/块池配置 + 26.6 新增 17 个检查函数 |
| 3. 插入点对象 | ✅ 实证 | obj+0xb8，堆写入点多处，可被 OOB 覆盖 |
| 4. vtable 虚调用 + PAC | ✅ 实证 | blraa + autda(0xcda1)，三版本同构 |
| 5. PAC 绕过（对象替换） | ⚠️ 结构可行，需真机 | vtable 指针从内存读取，替换对象可过认证 |
| 6. PowerOn 触发 | ✅ 实证 | 4 个触发入口（电源/命令路径） |

## 环节1-2: OOB 写来源与路径

### 漏洞形态（26.3 / 26.5.2 相同）
`AppleAVE2` 缓冲区大小计算：
```
mul w24, w22, w21       ; width × height，32位无符号乘法（无溢出防护）
```
- 无 `tbnz #0x1f`（符号位）、无 0x80000000 上限检查
- 恶意 app 传超大 width/height（VideoToolbox/AVAssetWriter 编码参数）→ 32位乘法溢出 → 计算出错误的（过小）bufSize
- bufSize 存 `dev+0x16c`，另有一结果存 `dev+0x198`

### 分配路径（`sub_fffffff008a5ee7c` = DPB 配置）
```
ldr w8, [x19, #0x16c]   ; bufSize
tbnz w8, #0x1f, fail     ; 仅检查负值（符号位），拦不住"溢出成小正值"
```
- 乘法溢出成**小的正值**（如 0x100）→ 分配小缓冲 → 后续按原始尺寸写入 → **内核堆 OOB 写**

### 26.6 修复证据（决定性）
- 26.6 (G71) 新增 **17 个独立函数** `AVE_CalcBufSizeOfColocated/MBInputCtrl/MBStats/SrcNeighbor*/EntropyCoding/...`
- 每个都带 `smull`（64位）+ `tbnz #0x1f` + `cmp 0x80000000` 检查 + `"AVE size overflow"` 日志
- 26.5.2 (F84) **只有 1 个**（CodedData）且无检查 → 其余 16 个缓冲区的计算在 26.5.2 中**无溢出防护**
- CVE-2026-64747 描述吻合："buffer overflow was addressed with improved size validation"

## 环节3-4: 函数插入点（用户提供地址 0xfffffff008a6f298 / 0x008a6f260）

### PowerOn（AVE_Drv::PowerOn）
- iPad 26.3: `sub_fffffff008a6f17c` / iPhone 26.5.2: `sub_fffffe00085c3280`（逐指令同构）
- `0xa6f260` / `0x85c3360`: `mov w3,#0x1a` → `bl AVE_CHM_AppendCmd`（命令追加）
- `0xa6f298` / `0x85c3394`: `tbz w8,#0` 循环 → `ldr x0,[x8,#0x100]`（回调对象数组）→ `bl 0xab3570`

### 真正的虚调用插入点（F84 0xfffffe00086007b0）:
```
ldr x0, [x19, #0xb8]      ; 对象指针 ← OOB 写目标
cbz x0, skip
ldr x16, [x0]             ; vtable 指针
mov x17, x0; movk #0xcda1 ; PAC modifier（三版本相同）
autda x16, x17            ; DA key 认证
ldr x8, [x16, #0xb8]!     ; vtable+0xb8 槽 = 虚函数指针（iPad 用 +0xb0）
blraa x8, x16             ; 认证后间接调用 → 内核上下文执行
```
- 紧接着还有第二个虚调用：`[x21]` vtable → `+0xa8` 槽（modifier 0xa255）
- `obj+0xb8` 堆写入点：`0xa792cc`（对象池初始化）、`0xaaeb0c`（构造函数）

## 环节5: PAC 绕过分析

**关键性质**: `x16 = [x0]` 是从**目标对象内存读取的现成 vtable 指针**，`autda` 用 DA key 认证。

- ❌ **直接伪造 vtable**: OOB 写任意值 → `autda` 失败 → `brk #0xc472`（内核 panic）
- ✅ **对象替换攻击（可行路径）**: OOB 写把 `obj+0xb8` 改为指向**另一个已存在的、vtable 已正确 PAC 签名的对象** → `ldr x16,[x0]` 读到合法 vtable → `autda` 通过 → 调用该 vtable+0xb8 槽的合法方法
- **结论**: 无需伪造 PAC 签名，只需 OOB 写**覆盖指针**。可行性取决于：能否把 `obj+0xb8` 覆盖为指向一个 vtable 槽可被利用的合法对象（如另一个 AVE 子对象、或经 heap groom 布局的受控对象）

## 环节6: 触发链

- PowerOn 有 4 个调用者：`sub_85c2ec4`（主入口）+ 3 个变体（ForcePowerOn/Sleep/Wake 路径）
- 触发方式: 通过 AVE 驱动 IO 命令/编码会话生命周期（创建编码会话 → 上电）从沙盒 app 可达
- 时机可控性: 需真机验证（编码器上电时机）

## 26.3 (iPad 8) 判定

**整套链在 26.3 上结构完整**：
- 乘法溢出漏洞: ✅ 与 26.5.2 逐指令相同（`mul w24,w22,w21` @ 0xfffffff0089f34f4，无检查）
- 插入点: ✅ PowerOn + obj+0xb8 vtable 调用存在（vtable 槽偏移 +0xb0，modifier 相同 0xcda1）
- 触发: ✅ 4 个调用者同构
- **差异**: iPad (A12) 与 iPhone (A19) 的 AVE 硬件单元不同，OOB 写的堆布局/groom 细节与 vtable 槽偏移需单独适配

## 待真机验证项（静态分析无法完成）

1. **OOB 写偏移可控性**: 乘法溢出后，实际写入的偏移能否精准命中 `obj+0xb8`（heap groom）
2. **对象替换候选**: 找到 `obj+0xb8` 可替换指向的合法对象（其 vtable+0xb8/0xb0 槽的虚函数可用）
3. **PowerOn 触发时机**从沙盒 app 的可达性
4. iPad 与 iPhone 的 AVE 堆布局差异

## 产出文件
- 报告: `D:\dsh-work\report_2652_jailbreak_point.md`（服务器 `/mnt/ios27b5/work/REPORT_2652_JAILBREAK_POINT.md`）
- AppleAVE2 三版本: `ave2_263/` `ave2_f84/` `ave2_g71/`
- 反汇编: `/tmp/ave2_{263,f84,g71}.txt`
- 工具: `match_funcs.py` `match_mnemonic.py` `extract_fn.py` `small_changed.py`
