# 接口契约与数据格式

> 各字段的位宽取值、定点格式与推导依据见 `FIXED_POINT.md`；参数唯一来源是
> `sw/b1i_ref/params.py` 与 `rtl/include/b1i_params.svh`。

本文件先定义稳定边界，再允许内部实现迭代。字段名、单位、时间基和有效标志必须固定；任何变更都要更新版本号和回归向量。

## 1. 输入文件

离线输入由二进制样本文件和同名 metadata 文件组成。metadata 至少包含：

```json
{
  "format_version": 1,
  "sample_encoding": "2bit-pair",
  "sample_rate_hz": 16384000,
  "if_hz": 4096000,
  "byte_order": "sample0_msb",
  "start_sample": 0,
  "source_time": "optional BDT/UTC tag",
  "sample_count": 0
}
```

每个字节按 `[7:6]`, `[5:4]`, `[3:2]`, `[1:0]` 解出四个连续样本：

```text
00 -> -3
01 -> -1
10 -> +1
11 -> +3
```

输入适配器必须检查文件长度、sample_count、编号连续性和 metadata 版本；截断文件应报错或在记录中明确 end-of-stream，不能静默补零。

## 2. RTL 顶层接口

建议模块名 `b1i_rx_top`，具体时钟频率由目标工艺确认。示意 SystemVerilog 端口：

```systemverilog
module b1i_rx_top #(
  parameter int N_CHANNELS = 12,
  parameter int SAMPLE_W = 3,
  parameter int SAMPLE_INDEX_W = 32,
  parameter int CONFIG_W = 32
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         sample_valid,
  input  logic signed [SAMPLE_W-1:0]   sample_i,
  input  logic [SAMPLE_INDEX_W-1:0]    sample_index,
  input  logic                         sample_last,
  input  logic                         cfg_valid,
  input  logic [CONFIG_W-1:0]          cfg_addr,
  input  logic [CONFIG_W-1:0]          cfg_wdata,
  output logic                         cfg_ready,
  output logic                         rec_valid,
  output logic                         rec_ready,
  output logic [255:0]                 rec_data,
  output logic                         rec_last,
  output logic [N_CHANNELS-1:0]        ch_locked,
  output logic [N_CHANNELS-1:0]        ch_bit_valid,
  output logic [N_CHANNELS-1:0]        ch_nav_valid,
  output logic                         error_valid,
  output logic [31:0]                  error_code
);
```

`sample_valid && ready`（若实现 ready/valid）才消耗一个样本；暂停时不能增加 sample_index。`sample_index` 从 0 连续递增，跨字节和跨 1 ms 不重置。`rec_valid && rec_ready` 才弹出记录。若采用无 back-pressure 的课程接口，也必须提供 FIFO 深度和 overflow 状态。

## 3. 结构化记录

`rec_data` 的具体打包可在 RTL 冻结时确定，但逻辑字段必须保持如下语义：

### Measurement record

```text
record_type = MEASUREMENT
epoch_id              // 公共接收历元，建议 1 s 序号
sample_index          // 该观测对应的接收样本时标
prn
channel_id
lock_state
measurement_valid
code_phase_chips      // 0..2046 的分数码相位
code_cycle_count      // 整毫秒/整周期计数
doppler_hz
carrier_phase_cycles  // 若实现
cn0_dbhz               // 若实现
pseudorange_m          // 若已具备时间锚点，否则标记 invalid
```

### Navigation record

```text
record_type = NAVIGATION
prn
bit_start_sample
subframe_id
nav_time_bdt
ephemeris_fields
clock_bias / clock_drift
health
decode_valid
parity_or_bch_status
```

### Status record

```text
record_type = STATUS
sample_index / epoch_id
channel_id
state_before / state_after
reason_code
overflow / timeout / loss_of_lock flags
```

所有记录都要携带 `valid` 或状态码。无锁、无时间锚点、无星历时，字段留空/invalid；不能把 0 当作合法测量。

## 4. 配置接口

至少支持：PRN 候选表、捕获多普勒起止/步长、码相位步长、积分长度、捕获门限、DLL/FLL/PLL 系数、失锁超时、输出历元周期和 debug 使能。配置写入必须有 reset 默认值、范围检查和读回机制。

## 5. RINEX 3.05 适配器

适配器输入为结构化 Measurement/Navigation records，输出：

- OBS：北斗系统标识 C；B1I 伪距至少写 `C2I`（单位 m）；若真实实现提供，可写 `D2I`（Hz）、`L2I`（周）、`S2I`（dB-Hz）。
- NAV：仅写实际解调出的 D1 星历、卫星钟差、时间和健康状态；缺测不能用模拟器真值补齐。
- 历元间隔默认 1 s；同一历元按 PRN 排序，失效卫星字段空置并带状态说明。

RINEX writer 必须有 header 生成器、字段宽度/精度测试、时间系统说明（BDT/UTC 转换策略）和独立 validator。学生 RTL 不拼接 RINEX 文本。

## 6. 软件 API 建议

```python
samples = read_2bit_if(path, metadata_path)       # iterator[Index, int]
acq = acquire(samples, prn_list, search_cfg)      # AcquisitionResult[]
tracks = track(samples, acq, track_cfg)            # PromptResult stream
nav = decode_d1(prompt_stream, nav_cfg)            # NavigationRecord stream
meas = build_measurements(tracks, nav, epoch_cfg)  # MeasurementRecord stream
write_rinex_obs(meas, obs_path)
write_rinex_nav(nav, nav_path)
```

参考模型 API 与 RTL 仿真导出 API 必须使用同一字段名和单位，方便逐周期/逐 1 ms 对比。

## 7. 错误码

建议至少保留：`BAD_METADATA`, `TRUNCATED_INPUT`, `SAMPLE_GAP`, `ACQ_TIMEOUT`, `ACQ_FALSE_ALARM`, `ACQ_MISS`, `TRACK_LOSS`, `NAV_SYNC_TIMEOUT`, `NAV_PARITY_ERROR`, `MEAS_NO_TIME`, `MEAS_NO_EPHEMERIS`, `FIFO_OVERFLOW`, `UNSUPPORTED_FORMAT`。
