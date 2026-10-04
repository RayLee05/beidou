# rtl/ —— 可综合 SystemVerilog

| 子目录 | 内容 |
|---|---|
| `include/` | `b1i_params.svh`（与 `sw/b1i_ref/params.py` 强制一致）、`b1i_records.svh` |
| `common/` | 解包、时基、载波表、PRN 发生器、SRAM 读口 |
| `acq/` | `acquisition.sv`（回放缓冲 + 并行码相位 + 多普勒扫描）。旧版 `acquisition_engine.sv` 不在 filelist |
| `track/` | 单通道跟踪、`channel_slice`（跟踪+NH+D1） |
| `ctrl/` | `channel_manager`（搜索表、移交、失锁释放） |
| `sync/` | `nh_bit_sync`、`d1_frame_sync` |
| `meas/` | `measurement_engine`、`epoch_aggregator`、`record_fifo` |
| `b1i_rx_top.sv` | 12 通道顶层 |

源文件清单：`rtl/filelist.f`（VCS / ModelSim / Vivado / Icarus 共用）。
