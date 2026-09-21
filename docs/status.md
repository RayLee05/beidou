# 实施状态

## 当前阶段

**P0/P1：需求冻结 + 架构与定点设计（对应课程 72 学时安排第 1–2 行，共 12 学时）—— 已完成。**

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
