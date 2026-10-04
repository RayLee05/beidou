# 北斗 B1I 基带处理与电文解调 ASIC 设计实践

离线 2 bit 中频样本 → 捕获 → 12 通道跟踪 → NH/D1 同步解调 → 公共历元测量记录 → RINEX 3.05 OBS/NAV，
再由配套定位软件完成单频码定位；同一份 RTL 继续走综合、布局布线、时序与物理验证。

**当前阶段：本机数字核心已接通并完成定向仿真（2026-10-04）。**
12 通道顶层 + 捕获/跟踪/NH/D1/测量记录在；本机 ModelSim / Vivado xsim / 软件链路证据见
[docs/LOCAL_VERIFICATION.md](docs/LOCAL_VERIFICATION.md)。正式综合与后端仍在虚拟机 `IC`。

## 运行环境

**正式 RTL 仿真与综合在虚拟机 `IC` 上做**（Synopsys VCS + Design Compiler），
入口是仓库根目录的 `make` 与 `scripts/dc_synth.tcl`；
本机只用于写代码、跑 Python 参考模型、生成测试向量。详见 [docs/TOOLCHAIN.md](docs/TOOLCHAIN.md)。

## 快速开始

```powershell
python scripts/run_all.py          # 全量检查：环境、参数一致性、定点预算、架构图、参考模型、RTL 用例
python scripts/run_all.py --quick  # 跳过绘图与 RTL 用例（无 iverilog/VCS 时）
```

```bash
# 虚拟机 IC 上（VCS）
make && make TEST=tb_tracking_channel
```

预期输出：4 项检查全部 PASS，日志写入 `reports/logs/run_all-<时间戳>.log`。

## 目录结构

| 目录 | 内容 | 当前状态 |
|---|---|---|
| `docs/` | 需求、架构、接口、定点、验证计划与进度 | 已建立（P0/P1 产出入库） |
| `rtl/` | 可综合 SystemVerilog（`include/ common/ acq/ track/ sync/ ctrl/ meas/`） | 12 通道顶层已接 |
| `tb/` | 单元与系统测试平台、测试向量 | 快测 + 跟踪/捕获/顶层 |
| `sw/` | 参考模型、IO、RINEX 适配器、PVT 适配、指标 | 可用 |
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
| 中频 / 采样率 | **4.092 MHz / 16.368 MSps**（1 ms = **16368** 样本） |
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

1. **IF/Fs**：以指导书为准，**4.092 MHz / 16.368 MSps**（课程 PPT 的 4.096/16.384 已废弃）。
2. **B1I ICD 2.1** 的 PRN / NH / D1 / BCH 已提取，见 `docs/ICD_EXTRACT.md`。
3. **目标工艺、PDK、EDA 工具与目标时钟**未确定（综合前从课程清单读取）。
4. **捕获搜索范围、环路带宽与性能门槛**待课程基线冻结。

详见 `docs/requirements.md` 第 16 节。

## 相关文档

- `docs/README.md`：文档索引
- `docs/AI_HANDOFF.md`：AI 编码交接说明（含执行顺序与完成定义）

## 仓库范围说明

本仓库**不包含**以下文件（见 `.gitignore`），它们仅存在于本地工作区。
建议统一放在根目录的 `references/`（整个目录已忽略，含讲义、实验指导书、ICD 与教材 PDF）：

| 文件 | 原因 | 队友如何获取 |
|---|---|---|
| `北斗B1I基带与位置解算基础.pdf`、`集成电路EDA实验课_课程安排.pdf` | 课程内部讲义，不在公开仓库传播 | 从课程渠道获取 |
| `VM-IC-SSH连接指南.md` | 含实验室虚拟机明文口令等内网凭据 | 由项目负责人私下发送 |

需求文档中引用的“C-课程 P?? / C-基带 P??”页码均指上述两份 PDF。

## License

[MIT](LICENSE) © 2026 RayLee05。课程内部材料（讲义 PDF、实验环境凭据）不在授权范围内，见上一节。

