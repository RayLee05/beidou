# 任务与代码审查（2026-10-04）

对照 `docs/requirements.md`、`docs/PLAN.md` 与当前 RTL/软件。本机仿真证据见 [LOCAL_VERIFICATION.md](LOCAL_VERIFICATION.md)。可并排打开审查页。

**总判：** 数字核心已接上，本机定向仿真为绿。课程验收仍缺：RTL 长测 hex 进定位、教师 SRAM、REQ-PERF/后端。没有 P0。

**二次审查后本机已修（同日晚，未提交）：**
- RTL `tx_ms` 与软件一致：`SOW*1000+(dump_ms-anchor_ms)+1`；`code_phase` 改为越界→历元的 Q(11.21)=`ds<<18`
- 调度：EPOCH+12×MEAS 连续写完再出 STATUS/NAV；`ep_wait=2` 等快照；FIFO 顶层 `wr_valid && wr_ready` 防回压误报溢出
- EPOCH 冻结 `sample_count`/`sow0_ms`（cfg `0x18`）；软件 OBS/PVT 优先 `sow0_ms`
- `refine_sagnac` 用当前接收机解迭代 Sagnac
- `run_local_chain` 捕获移交：8 ms 非相干 FFT 码相位 + 120 ms 短跟踪在 ±500 Hz 里挑选多普勒（不用真值半码片）
- 复测：ModelSim 快测 8/8、`tb_b1i_rx_top` PASS；7 s×4 |Δr|=35.125 m、dt=119.96 µs

**仍未在本机做：** RTL 7 s 全链路 hex（墙钟不可接受）；SF1–3 收齐（需 ~18 s）；删遗留 `acquisition_engine.sv`；NAV `generation` 4 bit 与 MEAS 8 bit 对齐（改 schema）。

**P1 修复（同日较早）：** 测量伪距走 SOW + dump 越界样本；RINEX 同一套 `t_rx`/`t_tx`；BCH 失败出 `EV_NAV_PARITY`；位/帧同步超时出 `EV_NAV_TIMEOUT`；通道事件按通道挂起。**未提交、未推送。**

## 1. 相对 72 学时计划

| 里程碑 | 计划出口 | 现状 |
|---|---|---|
| M0–M1 需求与架构 | 需求清单、接口、定点、`run_all.py` | 交付物在。多份文档未随 16.368 MHz / 顶层实现回写 |
| M2 单通道链路 | 无噪声下捕获→跟踪与黄金模型一致 | **已达。** `tb_tracking_channel` 300 窗逐位一致；`tb_acquisition` PASS |
| M3 电文与测量 | NH/D1/BCH、测量记录、RINEX | **已达本机出口。** BCH 拒识、同步超时、OBS 时间已修 |
| M4 12 通道与定位评价 | 12 通道无丢样、同历元可定位 | 顶层 12 通道在。软件测量伪距 |Δr|=35.1 m；hex→PVT 同口径 |
| M5–M7 综合/后端 | 网表、STA、DRC/LVS | 本机不做。`constraints/b1i_rx.sdc` 为 100 MHz 占位 |
| M8 答辩 | 可复现演示 | 未开始 |

## 2. 需求族覆盖

| 族 | 判定 | 依据 |
|---|---|---|
| REQ-SIG | 已覆盖 | `b1i_params.svh` / `params.py` 0.2.0：4.092 MHz、16.368 MSps、16368 样本/ms、2 bit 映射、PRN 2046、NH20、D1 50 bps |
| REQ-IN | 部分 | `sample_unpacker`、`sram_reader` 在。字宽/读延迟未按教师清单冻结。`error_code` 只有 FIFO 溢出 |
| REQ-IF / REQ-TRUTH | 部分 | 记录带 `generation`。表 2-2 八组接口被折进顶层，不是逐组端口。`run_local_chain.py` 用真值初始化并取几何伪距 |
| REQ-TB | 已覆盖（文档过时） | `sample_timebase.sv` 用 `SAMPLES_PER_MS`。`REQ-TB-002` 仍写 16384 |
| REQ-ACQ | 部分 | `acquisition.sv`：回放 + `N_LANES` 并行半码片 + 多普勒扫描。门限可配。虚警/漏警/C/N0 未报 |
| REQ-TRK | 已覆盖 | 12×`channel_slice`；`track_loop` 为 DLL+FLL/PLL+锁定滞回；失锁由 `channel_manager` 释放 |
| REQ-SYN | 部分 | `nh_bit_sync` / `d1_frame_sync` 有。无 `NAV_SYNC_TIMEOUT`。BCH 失败仍 `sf_valid` |
| REQ-NAV | 部分 | RTL 输出 224 bit + FraID/SOW/WN。星历在 `d1_nav.Ephemeris.from_subframes`。软件链路用了场景星历真值 |
| REQ-MEAS | 部分 | `measurement_engine` 冻结码相位/多普勒/`tx_ms`。`time_valid` 需锚点。软件 `(t_rx-t_tx)*c` 两套时间 |
| REQ-OUT | 部分 | RTL 只出 256 bit 记录。`rec_last=0`。OBS 为 MIXED、日期写死、无独立回读 |
| REQ-PERF | 缺失 | 捕获率、灵敏度、锁定保持、RMSE 均无报告 |
| REQ-IMPL | 受阻 | RTL 可综合取向；无浮点。工艺/时钟未冻结 |
| REQ-VERIF | 部分 | 定向全绿。无随机测、无 RTL 断言、无含噪统计区间 |
| REQ-DOC | 部分 | 需求/架构在。README、status 后半、PLAN §9.1 停在 9 月 |

## 3. 问题清单

### P1

1. **定位 0 m 不是 RTL 测量闭环** — `scripts/run_local_chain.py` 约 124–170 行。伪距 = 场景几何 + 钟差改正；跟踪用真值码相位初始化。可证明参考模型，不能证明顶层记录能定位。
2. **RINEX 伪距时间基准错位** — `sw/rinex/writer.py` 50–54 行。`t_rx = sample_count/Fs`，`t_tx = tx_ms/1000 + 码相位/2046`。RTL `tx_ms` 是 BDT 周内毫秒，两者相减不是伪距。
3. **BCH 失败仍输出有效电文** — `rtl/sync/d1_frame_sync.sv` 129–154 行。只累加 `fixes`，FraID∈[1,5] 就 `sf_valid`。违反 REQ-SYN-004。
4. **没有位/帧同步超时** — `nh_bit_sync.sv` 只有 `synced` 置位。REQ-SYN-002 的 `NAV_SYNC_TIMEOUT` 未实现。
5. **同拍 STATUS 事件覆盖** — `channel_manager.sv` 138–171 行，`evc_n` 后写覆盖。多通道同时锁定/释放会丢事件。
6. **对外文档仍写旧规格** — `README.md` 写「RTL 尚未开始」和 4.096/16.384。`docs/status.md` 后半、`PLAN.md` §9.1、`TRACKING_DESIGN.md` 仍把 ISSUE-001/002 写成打开。

### P2

7. ~~`rec_last` 恒 0 / error_code=12。~~ 已改：历元最后一条 MEAS 拉 `rec_last`；`error_code=ERR_FIFO_OVERFLOW(10)`。
8. ~~软件不消费 `generation`。~~ `filter_current_generation` 已用于 OBS/NAV/PVT。
9. `rtl/acq/acquisition_engine.sv` 仍不在 `filelist.f`（遗留）。架构图已改为 `acquisition.sv` / `track_loop`。
10. ~~RINEX MIXED / 无 BDT / 无回读。~~ 头为 C:BDS+BDT；`scripts/check_records.py` 回读。
11. ~~FIFO 深 16、满后误报 overflow。~~ 深 32；满时同拍读可腾位。

### P3

12. `REQ-TB-002`、`INTERFACES.md` 示例、`FIXED_POINT.md`、`constraints/b1i_rx.sdc` 注释、`tb_sample_timebase.sv` 失败打印仍残留 16384。实现已是 16368。

## 4. 建议顺序

交作业前：回写 README/status/PLAN → BCH 拒识 + 同步超时 → 修 OBS 时间或标明「OBS 暂不定位」→ 事件队列。

有任务包后再做：教师 SRAM 样例、RTL 记录进 PVT、REQ-PERF 曲线、虚拟机综合。不要在本机填工艺数。
