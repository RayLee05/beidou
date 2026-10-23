# 发现与决策

## 需求
- 用户要把仓库剩余代码在本机写完，本机有 ModelSim 与 Vivado。
- 正式综合/后端仍在虚拟机 IC。本轮是对照课程任务详细审查，不改功能代码。

## 研究发现（2026-10-04 审查）
- 数字核心已接：解包、时基、`acquisition.sv`、12×`channel_slice`、测量/FIFO、顶层。
- ISSUE-001/002 在现行 48 bit 码 NCO + `track_loop` 上未复现；文档后半仍写成打开。
- `run_local_chain` 已改为 SOW + `dump_ms`/`sample_end` 测量伪距（不再用几何真值）。7s×4 星：|Δr|=35.1 m，钟差 119.96 µs（真值 120），ΔPR 6–10 m。
- `write_obs` 用 EPOCH `rx_time_s` 与同一套 `tx_ms`+Q(11.21)。
- 码周期越界后 NCO 回绕，精细距离在 `sample_end`，不是码相位残差。dump 标签是窗口起点，越界时卫星时间 +1 ms。
- P2 本机已收：`rec_last`、FIFO 深 32、generation 过滤、hex→PVT 35.125 m、RINEX 回读。
- 二次审查已落地：RTL `tx_ms+1` / `ds<<18`、历元包不插队、EPOCH 冻结+`sow0_ms`、FIFO 回压门控、`refine_sagnac`、FFT+短跟踪移交（不用真值）。7 s×4 仍 35.125 m。
- `acquisition_engine.sv` 仍不在 `filelist.f`（遗留，不影响现行捕获）。
- 本机做不了：教师 SRAM、REQ-PERF、虚拟机综合。

## 教师 student_release（2026-10-09）
- 输入：`scenario.if2` 100 s、6 星、40 dB-Hz、16.368 MSps / 4.092 MHz；量化与字节序与我们 `sample_unpacker` 一致。
- 顶层固定为 `student_receiver_core`：`stream_data[31:0]/valid/ready/last` + 64 bit `sample_index`，输出 `record_data[255:0]/valid/ready`。
- 记录格式 `receiver_records_32byte_le_v1`：type 在 bits 7:0，6 类（tracking/navigation/lost/common_observation/acquisition/end），与我们 `b1i_records.svh` 完全不同。
- 教师 `route_a_position.py` 能从每毫秒 tracking 记录（Prompt I/Q + carrier_phase）软件恢复 D1；common_observation 必须落在整秒样本 `epoch_id*16368000`。
- 缺 `sim/if2_file_player.sv`、`sim/receiver_tb_template.sv`；README 写每拍 16 样本，json/接口注释写 4 样本，需要确认。
- 我们的参考模型 20 ms 捕获到 PRN 8/11/13/21/28；第 6 颗未见，疑为 PRN>37（码表只到 37）。

## 技术决策
| 决策 | 理由 |
|------|------|
| 规划文件放仓库根目录但不提交 | 会话工作记忆，不污染课程仓库 |
| 审查只写 docs/CODE_AUDIT.md，不改 RTL | 用户要审查；修复等明确指令 |
| 先参考模型，后 RTL | 后续模块依赖 Prompt/码相位 |

## 遇到的问题
| 问题 | 解决方案 |
|------|---------|
| Task 子代理因模型额度失败 | 改为直接读 RTL/软件 |
