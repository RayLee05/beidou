# 系统架构设计

> 架构总览图：`reports/figures/architecture.png`（由 `scripts/make_architecture_figure.py` 生成，可随架构演进重绘）。
> 位宽、累加器与周期预算见 `FIXED_POINT.md`；需求编号见 `requirements.md`。

## 1. 总体数据流

```mermaid
flowchart LR
  F[2-bit IF 文件\nmetadata + bytes] --> U[输入解包\n4 samples/byte]
  U --> T[公共样本时基\nx[n], sample_valid, n]
  T --> A[并行捕获引擎\nPRN x code phase x Doppler]
  A --> S[通道管理器\n12 channels]
  S --> C[码/载波跟踪\nDLL + FLL/PLL]
  C --> P[每 1 ms Prompt\nE/P/L + lock]
  P --> N[NH20/位同步]
  N --> D[D1 电文\n帧/去交织/BCH]
  C --> M[测量生成\ncode phase + cycle count]
  D --> O[测量/导航记录\ncommon epoch + valid]
  M --> O
  O --> R[RINEX 3.05 适配器]
  R --> OBS[OBS C2I/D2I/L2I/S2I]
  R --> NAV[NAV ephemeris/clock/health]
  OBS --> PVT[教师提供/配套定位软件\n单频码定位]
  NAV --> PVT
```

## 2. 分层边界

### RTL 数字核心

RTL 只处理样本、码、环路、同步、电文和结构化记录，不生成 RINEX 文本，不执行浮点定位。建议所有运行参数通过寄存器/配置 record 输入，避免把实验参数写死在数据通路中。

模块层次建议：

```text
rtl/
  b1i_rx_top.sv              // 顶层：输入、配置、12 通道、记录输出
  sample_unpacker.sv         // byte -> 2-bit -> signed amplitude + sample index
  sample_timebase.sv         // sample_valid、1 ms tick、epoch/sample counters
  prn_code_rom.sv            // PRN 码表，来源和版本可追踪
  nh20_rom.sv                // NH20 码表
  acquisition_manager.sv     // 任务调度、资源仲裁、峰值判决
  acquisition_engine.sv      // 单个搜索引擎，码相位/多普勒假设
  channel_manager.sv         // PRN 到 CH0..CH11、状态、重捕获
  tracking_channel.sv        // 参数化单通道包装器
  carrier_mixer_nco.sv       // sin/cos NCO、FLL/PLL 频率/相位更新
  code_nco.sv                // PRN/NH 码率 NCO、码相位和整数计数
  correlator_epl.sv          // Early/Prompt/Late 累加与积分边界
  dll_loop.sv                // E-L 误差、滤波、码速修正
  fll_pll_loop.sv            // 频率拉入、相位精跟踪、锁定判决
  nh_sync.sv                 // 20 个 1 ms Prompt 去 NH 并判数据位
  d1_frame_sync.sv           // 子帧同步、字/位组织、去交织、BCH/校验
  nav_decoder.sv             // 时间、星历、钟差、健康字段
  measurement_engine.sv      // 码相位 + 整周期 + 时间锚点 -> 伪距输入
  epoch_aggregator.sv        // 同一历元多星记录、公共同步、有效性
  record_fifo.sv             // 结构化测量/电文记录输出
```

### 软件参考模型与适配器

软件用于生成可验证的黄金模型、输入文件、指标和标准接口。推荐 Python 负责编排、NumPy 负责向量参考模型，若工具链要求可另配 C++/DPI 模型。

```text
sw/
  b1i_ref/                    // PRN/NH、捕获、DLL/PLL、同步、电文参考模型
  io/                         // 2-bit 文件和 metadata 解析
  rinex/                      // RINEX 3.05 OBS/NAV writer + validator
  pvt/                        // 基础单频码定位或教师软件适配层
  metrics/                    // 捕获、锁定、BER、伪距、RMSE、可用率
```

软件和 RTL 通过稳定的结构化记录交互（CSV/JSONL 仅用于调试，二进制 record 用于回放性能测试）。RINEX 生成器是唯一负责文本格式和缺测留空的模块。

## 3. 关键时基与信号参数

| 项目 | 默认值 | 设计约束 |
|---|---:|---|
| RF B1I | 1561.098 MHz | 仅用于文档/参数，不在基带时钟中直接采样 |
| IF | 4.096 MHz | 以课程规格为默认；4.092 MHz 是来源 PDF 的待确认冲突 |
| 采样率 | 16.384 MSps | 1 ms 恰好 16,384 samples |
| 量化 | 2 bit/sample | `00=-3, 01=-1, 10=+1, 11=+3` |
| 字节打包 | 4 samples/byte | 早样本在 `[7:6]`，随后 `[5:4]`, `[3:2]`, `[1:0]` |
| PRN | 2.046 Mcps | 2046 chips/1 ms |
| D1 | 50 bit/s | 20 ms/bit |
| NH20 | 20 chips/20 ms | 1 个数据位包含 20 个 NH 码片/20 个 PRN 周期 |
| 通道 | 12 | CH0..CH11，共享输入和公共时基 |
| 输出历元 | 1 s | 同历元多星观测聚合，缺测显式无效 |

## 4. 控制状态机

顶层和每通道均使用显式状态，禁止用隐含的“数据有效即默认锁定”。

```text
RESET -> IDLE -> ACQUIRE -> TRACK_PULL_IN -> TRACK_LOCKED
                                  |                |
                                  v                v
                              REACQUIRE <------ LOST

TRACK_LOCKED -> BIT_SYNC -> FRAME_SYNC -> NAV_VALID
任何状态 -- reset/timeout/invalid --> IDLE 或 REACQUIRE
```

每个状态需带：进入条件、退出条件、超时计数器、输出 valid 规则和可观测 debug 字段。失锁时撤销该通道当前有效测量，不能继续输出伪有效数据。

## 5. 数字实现取舍

- 首版捕获可采用时分复用搜索引擎 + 通道状态 RAM；如果吞吐或捕获时间不达标，再增加并行引擎。
- 跟踪阶段必须保持每个输入样本连续处理。环路更新可在 1 ms Prompt 边界进行，数据通路仍以 sample_valid 驱动。
- 乘法器、NCO、相关累加器和环路滤波器的位宽先由 Python 定点模型量化分析，再确定 RTL 位宽；所有截位必须有舍入/饱和策略和测试。
- 相关积分计数器必须覆盖 16,384 samples/1 ms、20 ms NH 边界和 30 s D1 帧时间，明确回绕行为。
- 12 通道必须共享样本解包、时间基和常量 ROM，通道私有环路状态；不要复制不必要的输入缓存。
