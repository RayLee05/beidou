# rtl/ —— 可综合 SystemVerilog

| 子目录 | 内容 |
|---|---|
| `include/` | 全局参数头（`b1i_params.svh`），与 `sw/b1i_ref/params.py` 强制一致 |
| `common/` | `sample_unpacker`、`sample_timebase`、NCO、LUT、FIFO 等基础模块 |
| `acq/` | `acquisition_manager`、`acquisition_engine` |
| `track/` | `channel_manager`、`tracking_channel`、`carrier_mixer_nco`、`code_nco`、`correlator_epl`、`dll_loop`、`fll_pll_loop` |
| `sync/` | `nh_sync`、`d1_frame_sync` |
| `nav/` | `nav_decoder` |
| `meas/` | `measurement_engine`、`epoch_aggregator`、`record_fifo` |
| `b1i_rx_top.sv` | 顶层（接口定义见 `docs/INTERFACES.md`） |

编码约定（P2 起强制）：

1. 仅可综合子集：无浮点、无动态数组、无类、无 `initial` 时序逻辑。
2. 统一 `clk`/`rst_n`；数据通路由 `sample_valid` 驱动，停顿时不推进样本号。
3. 所有位宽取自 `include/b1i_params.svh`，禁止在模块内硬编码魔数。
4. 每个截位/舍入点必须有注释说明依据（见 `docs/FIXED_POINT.md` 第 9 节）。
5. 每个模块先有 directed test，再有 random test；测试位于 `tb/unit/`。
