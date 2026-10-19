# 实施状态

## 当前验收 2026-10-19

本次按用户要求简化为单星捕获展示。入口为项目根目录“单星捕获验收/打开验收波形.cmd”，讲解提纲只保留六个信号和三处关键代码。
实测第11轮捕获位置10，相关能量为3281914944，最大未对齐值为3415104，比值961倍；随后两个窗口继续核对，共49104个对齐样本无差异。
信号来自老师的简化单星源，演示入口使用真实RTL仿真与ModelSim波形。原完整工程资料保留在README折叠部分。

原完整接收机代码与历史验证资料继续保留。捕获文档按用户最新 Word 修订稿拆分为“设计方案”和“实验报告”两个文件，各 7 页。设计方案保留原并行捕获内容，并将单星部分展开为 4 页，补充处理框图、接口、计数与时序、能量与位宽依据。实验报告已写好目的、步骤、实际仿真数据、结果分析与结论，仅留四处波形截图空位。本次重新运行单星 RTL 仿真，对齐能量为最大未对齐能量的 961 倍。拆分前用户原稿及旧 Markdown 存于模块实验报告的“历史版本”目录。

## 历史状态 2026-10-13

当前实现基线为 2556e76，已推送 GitHub。新版教师包 `student_release1/student_release/` 默认采用 16 样本／32 位、最低位对最早、标签步长 16；播放器顺序独立检查和含背压的 65 540 字节短流联调通过。
ModelSim 20／20 RTL 回归通过。四份 Word 及 Markdown 报告、总体架构图、接口／定点／验证材料已按当前实现修订。
现有短流仅输出 END；完整 100 s 的六星结果仍是浮点软件参考，当前 RTL 全量信号验收及目标工艺 DC 结论仍待完成。
该阶段验收材料存档为 `deliverables/模块实验报告/原完整项目讲解提纲_20261013.md`；对应证据在 `验证资料_20261013/`。以下条目按原日期保留，为历史进度，不覆盖本节当前结论。

## 历史阶段 2026-10-04

**本机可做的功能验证已跑完（2026-10-04）。** 详见 [LOCAL_VERIFICATION.md](LOCAL_VERIFICATION.md)。

数字核心已接成 12 通道顶层。ModelSim：快用例 8/8、跟踪 L2、顶层冒烟、捕获端到端均 PASS。
Vivado xsim 快用例 8/8 PASS。软件链路用 SOW 锚点 + dump 越界样本算伪距；捕获移交已改为 FFT+短跟踪（不用真值）；hex→PVT 同口径 |Δr|=35.125 m。RTL 侧 `tx_ms+1`、历元包连续、EPOCH/`sow0_ms` 已对齐。改动未提交未推送。
ISSUE-001 / ISSUE-002 已关闭（48 bit 码 NCO + 解包握手修复）。后端综合/P&R 仍只在虚拟机 IC 上进行。

## 完成清单

- [x] 已阅读并提取两份项目 PDF（课程安排、基带与位置解算基础）。
- [x] 已生成 `AI_HANDOFF.md`、`ARCHITECTURE.md`、`INTERFACES.md`、`VERIFICATION_PLAN.md`、`requirements.md`。
- [x] **需求清单**：`docs/requirements.md`，73 条需求分 13 族，含来源、优先级、状态与追踪矩阵。
- [x] **组内计划**：`docs/PLAN.md`，2 人分工、72 学时映射、M0–M8 里程碑与出口条件、风险登记册。
- [x] **架构图**：`reports/figures/architecture.png`（脚本可重新生成）。
- [x] **接口契约**：`docs/INTERFACES.md`（输入、顶层端口、记录 schema、配置、RINEX、错误码）。
- [x] **位宽与周期预算**：`docs/FIXED_POINT.md` 论证 + `reports/fixed_point_budget.md` 自动报告。
- [x] 工程骨架：`rtl/ tb/ sw/ data/ scripts/ constraints/ reports/ configs/` 全部建立并附说明。
- [x] 参数单一来源与一致性检查：`params.py` ↔ `b1i_params.svh` ↔ `b1i_default.json`。
- [x] 统一运行入口 `scripts/run_all.py`，一键跑通环境/参数/预算/绘图 4 项检查。
- [x] git 仓库初始化，提交 P0/P1 基线。

## 未完成 / 待确认

- [x] IF/Fs：以指导书 **4.092 MHz / 16.368 MSps** 为准（params 0.2.0）。
- [x] B1I ICD 2.1 码表 / NH / BCH：已写入 `prn_b1i.py` / `d1_nav.py`（见 `ICD_EXTRACT.md`）。
- [x] 本机仿真器：ModelSim 2020.4 + Vivado 2020.1 xsim。
- [x] 参考模型与确定性向量：`gen_track_vectors.py` / `gen_unit_vectors.py` 已重跑。
- [ ] 目标工艺、PDK、目标时钟（综合前必须从课程清单读取）。
- [ ] 捕获门限 / 环路带宽 / 灵敏度及格线（课程基线未冻结）。
- [ ] 教师 SRAM 样例上的系统级定位评价。

## 环境快照（2026-10-04 本机）

| 项 | 值 |
|---|---|
| python | 3.14.4（numpy / matplotlib 可用） |
| RTL 仿真 | ModelSim SE-64 2020.4；Vivado xsim 2020.1 |
| 正式综合 | 虚拟机 IC 上 VCS + DC（本机不做） |
| 版本控制 | git，HEAD `9e2f2c5`，工作区有未提交改动 |

## 本轮证据（P0/P1，2026-09-21）

| 命令 | 结果 | 证据 |
|---|---|---|
| `python scripts/run_all.py` | 4/4 PASS | `reports/logs/`（日志头部含运行时 git revision、参数 sha256 与工具版本） |
| `python scripts/check_params_consistency.py` | 参数三方一致 + 内部不变量通过 | 同上日志 |
| `python scripts/fixed_point_budget.py` | 位宽自洽性检查通过，报告生成 | `reports/fixed_point_budget.md`、`reports/fixed_point_budget.json` |
| `python scripts/make_architecture_figure.py` | 生成 2078×1165 架构图 | `reports/figures/architecture.png` |
| `git log --oneline` | `init: 北斗B1I基带处理与电文解调ASIC项目 — P0/P1` 及归档日志提交 | git 历史 |

> 复现方式：在干净检出中执行 `python scripts/run_all.py`；
> 报告头部记录参数文件 sha256、git revision 与工具版本。

## 下一轮任务

1. 教师 SRAM 样例上的 RTL 记录 → 定位（任务包未到）。
2. REQ-PERF 曲线与课程及格线。
3. 虚拟机 IC 上综合 / STA / P&R。

> 下面「第 3 行交付记录」起是 2026-09 当时的日志，其中 ISSUE-001/002 与「RTL 未开始」以本节和 [LOCAL_VERIFICATION.md](LOCAL_VERIFICATION.md) 为准。


## 第 3 行（捕获相关与跟踪）交付记录（2026-09-27）

| 项 | 结果 | 证据 |
|---|---|---|
| RTL 模块 | 11 个（解包/时基/载波表/NCO/混频/码 NCO/码 RAM/E-P-L 相关/DLL/FLL-PLL/跟踪通道） | `rtl/common/`、`rtl/track/` |
| RTL 通过用例 | `tb_carrier_lut`、`tb_sample_timebase`（定向，PASS） | `reports/rtl_unit_results.json` |
| L2 回归 | `tb_tracking_channel`：第 1 个 1 ms 的 E/P/L 相关值与定点模型**逐位一致**，此后出现分歧（ISSUE-001） | `tb/system/tb_tracking_channel.sv` |
| 参考模型 | 载波表/码源/信号生成/定点跟踪/捕获搜索 | `sw/b1i_ref/`、`reports/ref_model_results.md` |
| 向量与元数据 | 输入字节流 + 每 1 ms 期望值 + SHA256 + 码源标注 | `tb/vectors/` |
| 工具链 | 正式用虚拟机 IC 的 **VCS + DC**（`make` / `scripts/dc_synth.tcl`）；本机 Icarus 12 兜底 | `docs/TOOLCHAIN.md`、`Makefile`、`rtl/filelist.f` |
| 设计文档 | 数据通路、定点与时序约定、环路参数、验证与问题 | `docs/TRACKING_DESIGN.md` |
| **ISSUE-001** | 跟踪通道：`code_phase` 观测端口读回恒 0（相关值在第 1 窗口仍正确），第 2 个窗口起全面偏离 | `docs/TRACKING_DESIGN.md` 第 7 节 |
| **ISSUE-002** | `tb_sample_unpacker` 握手未完成导致仿真超时（已加超时保护，不再挂死套件） | `docs/TRACKING_DESIGN.md` 第 7 节 |

**下一轮任务**：修掉 ISSUE-001 → 实现 `acquisition_engine.sv`（串行码相位扫描，Python 参考已给出正确码相位）
→ 用 `generate` 展开 12 通道并接入共享时基。


## 2026-09-27 参数修正后的复核（重要）

按实验指导书把 fIF/Fs 改为 **4.092 MHz / 16.368 MHz（16368 样本/ms）** 后重跑：

| 检查 | 结果 |
|---|---|
| 参数一致性 | **PASS 67 项**（新增"每码片 8 样本""fIF = Fs/4"两条不变量） |
| 定点与周期预算 | 重新生成（1 样本 = 18.316 m；SAMPLE_INDEX 回绕 262.400 s；CORR/BIT 位宽不变） |
| 参考模型自检 | **PASS 13/13**（捕获码相位 **123.000 chip** 命中真值；跟踪收敛 −0.015 chip / 1.35 Hz） |
| RTL 用例 | `tb_carrier_lut`、`tb_sample_timebase` 待复跑；`tb_tracking_channel` **FAIL**（ISSUE-001 现象随参数变化，见下） |
| `tb_sample_unpacker` | **FAIL**（ISSUE-002 握手超时） |

**ISSUE-001 新现象**：改到 16.368 MHz 后，RTL 的 `code_phase` 观测在每个窗口读回
**16368 的三角数倍**（16368 / 49104 / 98208 / 163680 / 245520 / 343728 = SAMPLES_PER_MS × T(k)）。
这等价于"码率增量每窗口为 k"，说明 **码 NCO 的频率字/初值通路没有拿到参数值**，
而相关抽头仍然自洽（这也是为什么早期窗口相关值曾逐位一致）。
下一步：把 `code_inc`、`init_code_phase`、`CODE_INC_NOMINAL` 引到观测端口打印，
确认是参数头未被 `code_nco.sv` 取到还是 `load` 未生效。

**顺带发现的 RTL 缺陷**：`rtl/track/fll_pll_loop.sv` 第 98 行
`mag_p > lock_thresh[CORR_ACC_W:0]` 对 26 bit 向量做 [26:0] 切片越界（Icarus 报 out of bound → 'bx），
应改为 `mag_p > {1'b0, lock_thresh}`。


## 2026-09-28 捕获引擎首版（VCS 实测通过）

- 新增 `rtl/acq/acquisition_engine.sv`：码相位串行扫描，复用跟踪通道的 mix/NCO/码 RAM，
  每个假设相干积分 1 ms，用 |I|+|Q|/2 判决，记录峰值与 found。
- 新增 `tb/unit/tb_acquisition_engine.sv`：4 个假设、码表全 1、常数输入 + 本地载波冻结，
  峰值可手算 = 16368 × 3 × 511 = **25092144**，实测逐位一致。
- **虚拟机 VCS 实测通过**：`make TEST=tb_acquisition_engine` → PASS；`tb_carrier_lut` → PASS。
- 修了一个跨工具可移植性问题：`rtl/track/code_ram.sv` 里 `mem` 同时被 `always_ff` 和 `initial`
  驱动，VCS 判 `Illegal combination of procedural drivers`（Icarus 放行），已删除 `initial`。
- 本地 Icarus 现状：3/5 通过（acquisition、carrier_lut、sample_timebase）；
  未通过的两个是 ISSUE-001（跟踪通道 code_phase）与 ISSUE-002（unpacker 握手）。

**下一步（本机已完成后）**：用任务包 SRAM 样例走顶层；综合/后端到虚拟机 IC。
本机证据总表见 [LOCAL_VERIFICATION.md](LOCAL_VERIFICATION.md)。
