# 本机验证记录（2026-10-04）

本文件记录**不依赖 IC 虚拟机**、在本机（Windows + ModelSim / Vivado / Python）上完成的验证。
正式综合与后端仍见 [TOOLCHAIN.md](TOOLCHAIN.md)。

## 1. 环境

| 项 | 值 |
|---|---|
| 日期 | 2026-10-04 |
| 工作区 | `E:\code\eda` |
| git | `9e2f2c5`（工作区有未提交改动） |
| Python | 3.14.4 |
| ModelSim | SE-64 2020.4，`C:\modeltech64_2020.4\win64` |
| Vivado xsim | 2020.1，`E:\fpga\vivado\Vivado\2020.1\bin` |
| Icarus | `C:\iverilog\bin`（可用，本轮主用 ModelSim） |
| 参数 | fIF=4.092 MHz，Fs=16.368 MSps，params 0.2.0 |

复现入口：

```powershell
cd E:\code\eda
python scripts/run_all.py --quick
python scripts/run_rtl_unit.py --sim modelsim --quick
python scripts/run_rtl_unit.py --sim modelsim tracking_channel
python scripts/run_rtl_unit.py --sim modelsim b1i_rx_top
python scripts/run_rtl_unit.py --sim vivado --quick
python scripts/run_local_chain.py --sec 7 --sats 4
python scripts/check_records.py
python scripts/pvt_from_records.py reports/rinex/local_chain.hex --eph reports/rinex/local_chain_eph.json
```

## 2. 向量（本机重新生成）

| 文件 | 内容 | 生成命令 |
|---|---|---|
| `tb/vectors/prn_codes.hex` | PRN 1/6/9/20/37 | `python scripts/gen_unit_vectors.py` |
| `tb/vectors/nav_bits.hex` 等 | D1 帧同步 + NH 位同步 | 同上 |
| `tb/vectors/track_*.` | PRN 20，300 窗口，C/N0=45 dB-Hz，ICD 码 | `python scripts/gen_track_vectors.py --ms 300` |
| `tb/vectors/acq_*.` | 捕获 650 ms 场景（沿用已有向量） | `python scripts/gen_acq_vectors.py` |

`track_meta.json`：初差 +0.3 chip / +100 Hz，参考模型 `final_locked=true`。

## 3. RTL 仿真结果

### 3.1 ModelSim 快用例（8/8 PASS）

`python scripts/run_rtl_unit.py --sim modelsim --quick`

| 用例 | 结果 | 墙钟 |
|---|---|---:|
| tb_carrier_lut | PASS | ~1.6 s |
| tb_sample_unpacker | PASS | ~1.6 s |
| tb_sample_timebase | PASS | ~1.6 s |
| tb_prn_code_gen | PASS | ~1.6 s |
| tb_nh_bit_sync | PASS | ~1.6 s |
| tb_d1_frame_sync | PASS | ~1.6 s |
| tb_record_fifo | PASS | ~1.6 s |
| tb_channel_manager | PASS | ~1.6 s |

ISSUE-002（解包握手超时）在当前 `tb_sample_unpacker` 下已通过。

### 3.2 ModelSim 跟踪 L2（PASS）

`python scripts/run_rtl_unit.py --sim modelsim tracking_channel`

- 结果：**PASS**，墙钟 **8.13 s**
- 向量：300 个码周期窗口，与 `sw/b1i_ref/tracking_model.py` 逐位比对
- 结论：旧 ISSUE-001（`code_phase` 读回异常、第 2 窗口起偏离）在现行 48 bit 码 NCO + `track_loop` 上**未复现**

### 3.3 ModelSim 顶层冒烟（PASS）

`python scripts/run_rtl_unit.py --sim modelsim b1i_rx_top`

- `b1i_rx_top`（N_LANES=4）强制装载 CH0 后送 3 ms 样本
- 有 EPOCH + 12 条 MEAS 记录流出

### 3.4 Vivado xsim 快用例（8/8 PASS）

`python scripts/run_rtl_unit.py --sim vivado --quick`

归档：`reports/local/vivado_quick.json`

| 用例 | 结果 | 墙钟 |
|---|---|---:|
| 上述 8 个 unit | 全部 PASS | 各约 5 s |

### 3.5 ModelSim 捕获端到端（PASS）

`python scripts/run_rtl_unit.py --sim modelsim acquisition`

归档：`reports/local/modelsim_acquisition.json`

| 项 | 结果 |
|---|---|
| 墙钟 | **153.66 s**（仿真时间 516.8 ms） |
| 目标 PRN 10 | `found=1`，h=3192，peak/mean=1013221/210098 |
| 移交 | 约 109 ms |
| 跟踪 300 ms 后 | **locked=1**，码误差 **0.0058 chip** |
| 缺席 PRN 6 | `found=0` |

## 4. 软件全链路（不跑 RTL）

`python scripts/run_local_chain.py --sec 7 --sats 4`

归档：`reports/local/local_chain.md`、`reports/rinex/local_chain.obs`

| 项 | 结果 |
|---|---|
| 4 星定点跟踪 | 全部锁定（各 6999 窗口） |
| 多普勒误差 | 最大约 0.67 Hz |
| NH 位同步 | 4/4，各约 349 bit |
| D1 子帧（从 Prompt 抽取） | 每星 1 帧 |
| 单频码定位 | 伪距来自跟踪码相位 + 子帧 SOW（见 `run_local_chain.py`） |

说明：2026-10-04 起不再用场景几何伪距顶替。捕获移交改为 8 ms 非相干 FFT + 短跟踪选多普勒（不用真值半码片）。Sagnac 用当前接收机解迭代。7 s×4 仍为 |Δr|=35.125 m、dt=119.96 µs。卫星位置在短样本下仍用场景星历（SF1–3 未收齐）。RTL 测量 hex 进定位仍待长仿真 / 教师样例。

## 8. 审查修复复测（同日晚）

| 命令 | 结果 |
|---|---|
| `python scripts/run_rtl_unit.py --sim modelsim --quick` | **8/8 PASS**（各 ~1.6 s） |
| `python scripts/run_rtl_unit.py --sim modelsim b1i_rx_top` | **PASS** 1.95 s；EPOCH+12 MEAS 仍流出 |
| `python scripts/run_ref_model.py` | **13/13 PASS**；捕获码相位约定已与 scenario 对齐 |
| `python scripts/run_local_chain.py --sec 7 --sats 4` | 4 星锁定+各 1 子帧；|Δr|=**35.125 m**；dt=119.96 µs |
| `python scripts/check_records.py` | 含 `sow0_ms` 回读；hex→PVT 35.125 m |
| `python scripts/pvt_from_records.py reports/rinex/local_chain.hex --eph reports/rinex/local_chain_eph.json` | ok，err_m=35.125 |

## 5. 本机已交付、无需虚拟机的工作

- 12 通道顶层与测量/记录通路
- 通道管理、强制装载调试口
- RINEX 适配器（`scripts/export_rinex.py`）
- 单频码定位骨架（`sw/pvt/lsq.py`）
- ModelSim / Vivado 统一入口（`scripts/run_rtl_unit.py`）

## 6. 本机做不到、留给虚拟机 / 课程任务包

| 项 | 原因 |
|---|---|
| DC 综合、ICC 布局、DRC/LVS | 工艺库与 DC 在 IC 虚拟机 |
| 教师 SRAM 样例与及格门槛 | 任务包未到 |
| 捕获 64 路长测 | **已在本机 PASS**（153.66 s），见 3.5 节 |

## 7. 捕获用例补记

| 命令 | 结果 | 墙钟 | 日志 |
|---|---|---:|---|
| `python scripts/run_rtl_unit.py --sim modelsim acquisition` | **PASS**（捕获命中 + 跟踪锁定 + 缺席 PRN 拒识） | 153.66 s | `reports/local/modelsim_acquisition.json` |
