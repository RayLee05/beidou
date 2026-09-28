# 验证、性能与交付计划

## 1. 验证分层

### L0：常量与格式

- PRN 码表、NH20 序列、2 bit 映射、字节顺序、1 ms/20 ms/30 s 计数器。
- metadata 错误、截断文件、sample_index 间断、end-of-stream。
- 所有定点量化、饱和、负数符号扩展和计数器回绕。

### L1：单模块 RTL

- `sample_unpacker`：四样本映射和连续索引。
- NCO：相位累加、频率调谐、回绕。
- PRN/NH 生成：周期、相位偏移和边界。
- 相关器：E/P/L 累加、积分边界、符号翻转。
- DLL/FLL/PLL：误差方向、限幅、锁定/失锁 hysteresis。
- NH/D1：20 ms 位边界、子帧起点、去交织、BCH/校验。

每个模块先做 directed test，再做随机 test；保存输入、期望输出和波形索引。

### L2：单通道链路

无噪声、已知 PRN/码相位/频偏/数据位的合成信号必须完成：捕获 -> 跟踪 -> NH -> D1 -> measurement/nav record。使用 Python 黄金模型逐 1 ms 对比码相位、频率、E/P/L、状态和数据位。

### L3：12 通道与系统

- 12 颗卫星在同一输入和公共时基下并行运行。
- 逐历元聚合排序、缺测、失锁、重捕获、FIFO back-pressure。
- OBS/NAV 适配器生成 RINEX 3.05，并用独立读取器回读。
- 多星伪距进入配套定位软件，检查三维位置、钟差和有效状态。

### L4：压力与鲁棒性

- C/N0 45/40/35/30/25 dB-Hz 扫描作为起始测试，最终门槛由课程基线冻结。
- 多普勒、码漂移、加速度、短时遮挡、样本停顿、失锁和重捕获。
- 捕获虚警/漏警统计、捕获耗时、锁定保持率、码误差、BER、字/帧错误率。
- 所有噪声测试固定随机种子，报告置信区间和条件。

### L5：ASIC 实现

- 综合：网表、面积、功耗估计，记录工具/库/约束版本。
- STA：目标时钟和分析角下 setup/hold 无违规，WNS >= 0、TNS = 0。
- 布局布线：时序后网表回归和吞吐检查。
- DRC/LVS：指定工艺规则下无违规，网表与版图一致。
- 报告必须对应最后冻结的 RTL、SDC、网表、版图和验证 commit。

## 2. 验收矩阵

| 需求 | 证据 | 阻断级别 |
|---|---|---|
| 2 bit 输入正确解包 | L0 向量 + 波形 | 阻断 |
| 1 ms/20 ms/30 s 时基 | 计数器断言 + L0/L1 | 阻断 |
| 捕获 PRN/码相位/多普勒 | 单通道报告 | 阻断 |
| DLL/FLL/PLL 锁定 | 环路状态和误差曲线 | 阻断 |
| NH20、D1、电文校验 | 黄金比对 + 解码日志 | 阻断 |
| 12 通道无丢样 | 吞吐计数、FIFO/overflow 证据 | 阻断 |
| C2I OBS / NAV | RINEX round-trip validator | 阻断 |
| 缺测不伪造 | fault injection + RINEX 检查 | 阻断 |
| 捕获/跟踪性能 | 固定条件性能报告 | 重要 |
| STA/DRC/LVS | EDA 报告 | 阻断（后端交付） |

## 3. 断言与不变量

- `sample_valid` 消耗一次且仅一次样本；有效输入时 sample_index 连续。
- 每个 1 ms 边界恰好产生一次 Prompt 记录或明确 invalid/timeout。
- 未进入 LOCKED/NAV_VALID 的通道不得生成有效测量/导航字段。
- 失锁事件后，之前通道的有效状态不能泄漏到新 PRN。
- 计数器回绕是定义行为，不能产生负时间或重复历元。
- FIFO overflow、配置越界和格式错误必须可观察且不可静默恢复。

## 4. 里程碑与交付物

| 阶段 | 结果 |
|---|---|
| P0 需求冻结 | `requirements.md`、参数表、冲突决策、版本基线 |
| P1 参考模型 | 可读输入、PRN/NH、合成向量、捕获/跟踪/同步黄金结果 |
| P2 单通道 RTL | L0/L1 通过，波形和断言齐全 |
| P3 12 通道 | 公共时基、资源预算、无丢样报告 |
| P4 观测/电文接口 | record schema、RINEX OBS/NAV、回读验证 |
| P5 系统评估 | 伪距/定位、性能扫描、故障注入 |
| P6 ASIC 前端 | 综合、SDC、STA、面积/功耗报告 |
| P7 后端 | P&R、DRC/LVS、后仿真/最终回归 |
| P8 交付答辩 | README、运行脚本、报告、复现记录、个人贡献/修复记录 |

## 5. 统一运行入口

建议提供：

```text
scripts/run_ref_model.*
scripts/run_rtl_unit.*
scripts/run_rtl_system.*
scripts/run_rinex_check.*
scripts/run_metrics.*
scripts/run_synthesis.*
scripts/run_physical_checks.*
scripts/run_all.*
```

每个入口都要打印版本、输入文件 SHA256、配置、随机种子、工具版本和输出目录。CI 至少执行格式检查、Python 单元测试、RTL lint/仿真和一个短系统向量；长时间捕获和 EDA 后端作为 nightly/人工阶段。

## 6. 风险清单

1. IF/采样率在两份材料中不一致：先参数化并冻结决策。
2. PRN/NH/D1 细节缺 ICD：禁止“看起来合理”的自创码表。
3. 16.384 MSps、12 通道和捕获搜索的资源冲突：用吞吐/面积预算决定时分复用程度。
4. 浮点模型与定点 RTL 偏差：先做定点黄金模型和位宽扫描。
5. RINEX 时间系统、卫星钟差和缺测规则容易被忽略：用独立 parser round-trip。
6. 位置解算结果不能反向证明基带正确：必须同时保留样本级、Prompt 级、导航位级和 OBS/NAV 级证据。
