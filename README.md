# 北斗 B1I 基带接收机与单星捕获实验

仓库同时保留原完整接收机工程和新增单星捕获演示。当前验收重点是：**尝试不同的码起始位置，展示对齐后的相关能量大幅增加，并输出捕获成功。**

原工程的并行捕获、多通道跟踪和电文解调链路继续保留，入口见 [完整项目讲解](deliverables/模块实验报告/原完整项目讲解提纲_20261013.md)。捕获文档分为[设计方案](deliverables/模块实验报告/01_捕获模块设计方案.docx)和[实验报告](deliverables/模块实验报告/01_捕获模块实验报告.docx)：方案详细说明原工程与单星方法，实验报告已写好实验步骤、结果和分析，仅留四处波形截图空位。

1. 在资源管理器中打开 `单星捕获验收` 文件夹，双击 **打开验收波形.cmd**。
2. 按 [验收讲解提纲](deliverables/模块实验报告/验收文件索引与讲解提纲.md) 操作，只看六个信号和三处关键代码。

| 实测项目 | 结果 |
| --- | --- |
| 第一次捕获 | 第 11 轮，找到起始位置 10 |
| 对齐后的相关能量 | 3,281,914,944 |
| 最大未对齐相关能量 | 3,415,104 |
| 能量比 | **961 倍，超过要求的 100 倍** |
| 后续复核 | 再验证两轮，码线继续对齐，能量保持 |

详细入口见 [先看这里](单星捕获验收/先看这里.md)。脚本会重新仿真，再打开真实的 ModelSim 波形文件。

<details>
<summary>原完整工程资料</summary>

# 北斗 B1I 基带处理与电文解调 ASIC 设计实践

离线 2 bit 中频样本 → 捕获 → 12 通道跟踪 → NH/D1 同步解调 → 公共历元测量记录 → RINEX 3.05 OBS/NAV，
再由配套定位软件完成单频码定位；同一份 RTL 继续走综合、布局布线、时序与物理验证。

**当前阶段：12 通道数字核心和教师流接口已接通，支持 PRN 1–63 自动搜索。**
捕获/跟踪/NH/D1/测量记录已有定向回归；教师 100 s 输入的完整 RTL 信号验收仍待运行。
此前本机 ModelSim / Vivado xsim / 软件链路证据见
[docs/LOCAL_VERIFICATION.md](docs/LOCAL_VERIFICATION.md)。正式综合与后端仍在虚拟机 `IC`。

## 运行环境

**正式 RTL 仿真与综合在虚拟机 `IC` 上做**（Synopsys VCS + Design Compiler），
入口是仓库根目录的 `make` 与 `scripts/dc_synth.tcl`；
本机可进行代码开发、Python 参考模型、向量生成和 ModelSim/Questa RTL 回归。
详见 [docs/TOOLCHAIN.md](docs/TOOLCHAIN.md)。

## 快速开始

```powershell
python scripts/run_all.py          # 全量检查：环境、参数一致性、定点预算、架构图、参考模型、RTL 用例
python scripts/run_all.py --quick  # 参数、参考模型、快速 RTL；跳过绘图和慢速 RTL
```

```bash
# 虚拟机 IC 上（VCS）
make && make TEST=tb_tracking_channel
```

预期输出：4 项检查全部 PASS，日志写入 `reports/logs/run_all-<时间戳>.log`。

## 教师任务包接口

新版任务包位于 `student_release1/student_release/`（不入 Git），运行脚本默认优先选择新版；
旧包 `student_release/` 仍可通过 `--release` 显式使用。本仓库的
`rtl/student_receiver_core.sv` 已实现同名接口，连接真实捕获、跟踪和同步译码模块；
编译使用 `rtl/filelist.f`，不要同时编译老师包中的同名空壳。

```powershell
# 新版教师播放器 + 本仓库 RTL，1 ms 接口检查（含输出停顿）
python scripts/run_teacher_receiver.py --max-bytes 4092 --stall-period 7

# 独立验证采样顺序、标号、背压与 64 KiB 缓冲区跨越
python scripts/run_teacher_receiver.py --max-bytes 65540 --check-stream-only

# 完整输入，要求至少四颗星捕获及跟踪、电文和公共历元输出
python scripts/run_teacher_receiver.py --require-signal-results --timeout 14400

# 单元与系统回归
python scripts/run_rtl_unit.py --sim modelsim
```

入口目前支持 ModelSim/Questa（通过 `MODELSIM_HOME` 或 `PATH` 定位），输出在
`reports/sim/teacher_records.bin`，并调用老师的 `tools/check_records.py`。
100 s 文件含 409,200,000 字节、1,636,800,000 个样本，事件仿真可能需要数小时；
短测通过仅证明接口和计数，不代表完整捕获、导航或定位通过。

2026-10-13 新版教师包已统一输入约定，接收机默认使用 `STREAM_MODE=2, TAG_STRIDE=16`：

- 每次 32 位握手传输 **16 个样本**，`[1:0]` 最早、`[31:30]` 最晚，标号每次增加 16。
- IF2 文件仍为字节内 MSB-first；新版播放器已重排为总线低位先行，接收端直接解包。
- 新模板等待 END；仓库也在全部样本及队列排空后结束。入口仍显式提供 `MAX_BYTES`，
  处理播放器在 64 KiB 整数倍输入上遗漏 `stream_last` 的边界问题。
- 每次运行先将原播放器解包输出与文件时间顺序逐样本独立比对，检查成功后才运行接收机。
  `--release student_release` 自动选择已验证旧播放器所需的 `STREAM_MODE=1, TAG_STRIDE=4`；
  四样本低位先行的旧接口仍可选择 `STREAM_MODE=0`。

新版差异、验证结果和复现命令见 [TEACHER_STREAM_UPDATE.md](docs/TEACHER_STREAM_UPDATE.md)。

公共输出采用教师的 32 字节小端格式：跟踪 schema 3、逐字导航、失锁、公共观测、
捕获和唯一 END。导航保留极性校正后的原始字（包括纠错前的错误位）、实际信息位、
每字纠错数，以及字结束时捕获的样本号和 Q11.37 码相位。
公共观测在同一个真实一秒边界冻结各通道的码相位与代次；只有锁定、NH、帧和时间
条件同时成立才声明有效。输出反压会暂停样本消费，已有记录保持到握手后再释放。
连续输入在捕获外推追赶和通道 NCO 装载期间也会暂停，随后从未消费的样本继续。
运行入口还用老师的译码器流式复核导航原始字、信息位、纠错数和子帧字段；
超时或验证失败的输出保留为 `.partial.bin`，验证通过后才替换正式 BIN。
旧字节/SRAM 输入及内部记录格式仍是 `b1i_rx_top` 的默认模式。

## 实验报告与验收材料

2026-10-13 修订的四份报告均为版本 2.1，内容对应实现基线 `2556e76`，并采用新版教师输入契约。

| 提交材料 | 文件 |
| --- | --- |
| 捕获模块 | [设计方案](deliverables/模块实验报告/01_捕获模块设计方案.docx)；[实验报告](deliverables/模块实验报告/01_捕获模块实验报告.docx) |
| DLL／FLL／PLL | [码跟踪锁频锁相环报告](deliverables/模块实验报告/02_码跟踪锁频锁相环报告.docx) |
| 位同步与导航电文 | [实验报告](deliverables/模块实验报告/03_位同步与导航电文解调报告.docx) |
| 总体设计 | [总体架构方案](deliverables/总体架构方案/北斗B1I基带处理器_总体架构方案.docx) |

[验收文件索引与讲解提纲](deliverables/模块实验报告/验收文件索引与讲解提纲.md) 列出各报告对应的 RTL、测试台、运行命令和结果范围。
最新 20 项 RTL 回归和 262 160 样本播放器检查证据位于 `验证资料_20261013/`；既有曲线与软件参考保留在 `验证资料_20261012/`。
短流输出仅为 END，完整公开 100 s 的当前 RTL 六星接收及最终工艺综合仍需独立完成。

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


</details>
