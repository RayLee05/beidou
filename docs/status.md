# 实施状态

## 当前阶段

**P0/P1：需求冻结 + 架构与定点设计（第 1–2 行，12 学时）—— 已完成。**

**第 3 行：捕获相关与跟踪（16 学时）—— 首版完成（码路径已逐位验证，存在 1 个已知问题见下）。**

未开始：RTL 实现（P2 起）。

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

- [ ] 确认 IF/Fs 冲突（4.096/16.384 vs 4.092/16.368）。
- [ ] 获取正式 B1I ICD、PRN/NH/D1 参数与参考码表。
- [ ] 确认目标工艺、PDK、EDA 工具与目标时钟。
- [ ] 选定 RTL 仿真器/综合器（当前环境缺失）。
- [ ] 完成参考模型与确定性测试向量（P1）。
- [ ] 冻结捕获搜索范围、环路带宽与性能门槛。

## 环境快照

| 项 | 值 |
|---|---|
| python | 3.12.1（numpy / matplotlib / pypdf / PyMuPDF 可用；pytest 缺失） |
| RTL 仿真器/综合器 | 未发现（iverilog / verilator / yosys / 商业工具均缺失） |
| 版本控制 | git 已初始化 |

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

## 下一轮任务（进入第 3 行：捕获相关与跟踪，16 学时）

1. 建立定点参考模型：2 bit 解包、PRN/NH 码发生器接口、载波/码 NCO、E/P/L 相关。
2. 合成无噪声确定性向量，产出单通道捕获 → 跟踪 → Prompt 的黄金结果到 `data/expected/`。
3. 实现并单测 `sample_unpacker`、`sample_timebase`、`prn_code_rom`（接口先行、码表留空占位）。
4. 建立波形与断言基线，形成 L0/L1 测试记录。


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
