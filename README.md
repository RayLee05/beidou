# 北斗 B1I 基带处理与电文解调 ASIC 设计实践

离线 2 bit 中频样本 → 捕获 → 12 通道跟踪 → NH/D1 同步解调 → 公共历元测量记录 → RINEX 3.05 OBS/NAV，
再由配套定位软件完成单频码定位；同一份 RTL 继续走综合、布局布线、时序与物理验证。

**当前阶段：P0/P1（需求冻结 + 架构与定点设计）已完成**，对应课程 72 学时安排的第 1–2 行（12 学时）。
实现代码尚未开始，见 `docs/PLAN.md` 第 10 节。

## 快速开始

```powershell
python scripts/run_all.py          # 全量检查：环境、参数一致性、定点预算、架构图
python scripts/run_all.py --quick  # 跳过绘图（无 matplotlib 环境）
```

预期输出：4 项检查全部 PASS，日志写入 `reports/logs/run_all-<时间戳>.log`。

## 目录结构

| 目录 | 内容 | 当前状态 |
|---|---|---|
| `docs/` | 需求、架构、接口、定点、验证计划与进度 | 已建立（P0/P1 产出入库） |
| `rtl/` | 可综合 SystemVerilog（`include/ common/ acq/ track/ sync/ nav/ meas/`） | 仅有参数头文件 |
| `tb/` | 单元与系统测试平台、测试向量 | 空骨架 |
| `sw/` | 参考模型、IO、RINEX 适配器、PVT 适配、指标 | 参数模块已建 |
| `data/` | 输入样本与黄金结果 | 空骨架 |
| `scripts/` | 统一运行入口与检查脚本 | 可用 |
| `constraints/` | SDC 与后端约束 | 空骨架 |
| `configs/` | 运行期配置 | 默认配置已建 |
| `reports/` | 自动生成的报告、图与日志 | 已生成首版 |

## 交付物索引（P0/P1）

| 交付物 | 位置 |
|---|---|
| 需求清单（73 条，可追踪） | `docs/requirements.md` |
| 组内计划（72 学时映射与里程碑） | `docs/PLAN.md` |
| 架构设计（数据流、分层、状态机） | `docs/ARCHITECTURE.md` |
| 架构图（PNG，可重新生成） | `reports/figures/architecture.png` |
| 接口契约与记录 schema | `docs/INTERFACES.md` |
| 位宽与周期预算（论证） | `docs/FIXED_POINT.md` |
| 位宽与周期预算（脚本生成） | `reports/fixed_point_budget.md` |
| 验证与验收计划 | `docs/VERIFICATION_PLAN.md` |
| 进度与证据记录 | `docs/status.md` |
| 参数单一来源 | `sw/b1i_ref/params.py` ↔ `rtl/include/b1i_params.svh` ↔ `configs/b1i_default.json` |

## 关键参数（课程规格基线）

| 项 | 值 |
|---|---|
| 中频 / 采样率 | 4.096 MHz / 16.384 MSps（1 ms = 16384 样本） |
| 量化与打包 | 2 bit/样本，4 样本/字节，早样本在高位 |
| 测距码 / 二级码 / 电文 | 2.046 Mcps / 2046 chip / 1 ms；NH20 20 chip/20 ms；D1 50 bit/s，帧 30 s |
| 通道与历元 | 12 通道共享样本流与公共时基；默认 1 s 公共历元 |
| 目标时钟 | 100 MHz（**占位，待冻结**） |

参数修改流程：改 `sw/b1i_ref/params.py` → 同步 `rtl/include/b1i_params.svh` 与
`configs/b1i_default.json` → 运行 `python scripts/check_params_consistency.py`（不一致即失败）。

## 复现与证据

- 每个自动报告打印生成时间、参数文件 sha256、git revision 与 python 版本。
- RTL、约束、网表、版图、验证报告必须指向同一版本标识（REQ-IMPL-007）。
- 测试固定随机种子；噪声测试报告条件与置信区间。

## 必须先确认的事项

1. **IF/Fs 冲突**：来源 PDF 为 4.092 MHz / 16.368 MSps，课程规格为 4.096 MHz / 16.384 MSps。
2. **正式 B1I ICD**（PRN 码表、NH20 序列、D1 字段、BCH 参数）尚未交付 —— 当前不写入任何码表。
3. **目标工艺、PDK、EDA 工具与目标时钟**未确定。
4. **捕获搜索范围、环路带宽与性能门槛**待课程基线冻结。

详见 `docs/requirements.md` 第 16 节。

## 相关文档

- `docs/README.md`：文档索引
- {{BT}}docs/AI_HANDOFF.md{{BT}}：AI 编码交接说明（含执行顺序与完成定义）

## 仓库范围说明

本仓库**不包含**以下文件（见 {{BT}}.gitignore{{BT}}），它们仅存在于本地工作区：

| 文件 | 原因 | 队友如何获取 |
|---|---|---|
| {{BT}}北斗B1I基带与位置解算基础.pdf{{BT}}、{{BT}}集成电路EDA实验课_课程安排.pdf{{BT}} | 课程内部讲义，不在公开仓库传播 | 从课程渠道获取 |
| {{BT}}VM-IC-SSH连接指南.md{{BT}} | 含实验室虚拟机明文口令等内网凭据 | 由项目负责人私下发送 |

需求文档中引用的“C-课程 P?? / C-基带 P??”页码均指上述两份 PDF。

