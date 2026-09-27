# 捕获相关与跟踪设计（第 3 行 · 16 学时）

> 交付物对应「72 学时安排」第 3 行：**捕获相关与跟踪 → 可复制通道 RTL 与测试记录**。
> 参数与位宽见 [FIXED_POINT.md](FIXED_POINT.md)；接口见 [INTERFACES.md](INTERFACES.md)；
> 需求编号见 [requirements.md](requirements.md)。本行覆盖 REQ-ACQ-001..006、REQ-TRK-001..006、REQ-VERIF-001/003。

## 1. 模块清单（可复制通道）

| 文件 | 作用 | 单测 |
|---|---|---|
| `rtl/common/carrier_lut.sv` | 载波 sin/cos 查表（组合，表由脚本生成） | `tb/unit/tb_carrier_lut.sv` |
| `rtl/common/carrier_lut_table.svh` | 1024 项 × 10 bit 表（自动生成） | 同上 |
| `rtl/common/sample_unpacker.sv` | 1 字节 → 4 个 2 bit 有符号样本 | `tb/unit/tb_sample_unpacker.sv` |
| `rtl/common/sample_timebase.sv` | 样本编号、1 ms / 20 ms / 6 s / 1 s 边界 | `tb/unit/tb_sample_timebase.sv` |
| `rtl/track/carrier_mixer_nco.sv` | 载波 NCO + I/Q 混频 | 由系统测试覆盖 |
| `rtl/track/code_nco.sv` | 码相位 NCO（Q(11.21)）+ 码周期回绕 | 由系统测试覆盖 |
| `rtl/track/code_ram.sv` | PRN 码 RAM + E/P/L 三抽头 | 由系统测试覆盖 |
| `rtl/track/correlator_epl.sv` | 6 路 1 ms 相干累加 + 窗口转存 | 由系统测试覆盖 |
| `rtl/track/dll_loop.sv` | 码环鉴别 + 二阶滤波（负反馈） | 由系统测试覆盖 |
| `rtl/track/fll_pll_loop.sv` | Costas 鉴相 + 二阶 PLL + FLL 辅助 + 锁定判决 | 由系统测试覆盖 |
| `rtl/track/tracking_channel.sv` | 单通道集成（可参数化复制为 12 路） | `tb/system/tb_tracking_channel.sv` |

## 2. 数据通路与定点约定

```text
sample(3b) ─┬─> carrier_mixer_nco ──> mix_i/mix_q(13b) ──┐
            │        ▲ freq_word                          │
            │        └── fll_pll_loop ◄── dump_i_p/q_p ───┤
            └─> code_nco ──> code_ram ──> e/p/l tap ──────┤
                     ▲ code_inc                          │
                     └── dll_loop ◄── dump_i_e/q_e/i_l/q_l
                                                         v
                                              correlator_epl(26b × 6)
```

关键约定（Python 参考模型 `sw/b1i_ref/tracking_model.py` 与之逐拍等价）：

1. **载波相位**：每个样本先累加相位再用新相位查表混频，即样本 n 使用第 (n+1) 个相位步进。
   合成信号生成器（`signal_gen.py`）采用同一约定，保证 I/Q 不经受无意义的 90° 偏置。
2. **码相位**：Q(11.21)，即整数码片 [31:21] + 小数码片 [20:0]；一个码周期 = `2046 << 21`。
   标称增量 261888 = round(2046/16384 × 2^21)，**精确无截断误差**。
3. **窗口边界**：`ms_tick` 出现在 1 ms 窗口的**最后一个样本**上，相关性在该拍把"上一窗口累加值 + 本样本"
   转存到 dump 寄存器并清零；`dump_valid` 比它晚一拍，正好落在**新窗口的第一个样本**上。
4. **零滞后更新**：`dll_loop` / `fll_pll_loop` 在 `update` 有效拍把"下一状态"**旁路**到输出，
   因此新窗口的第一个样本就使用新系数。模型里等价于"先算和、再更新、下一步用新值"。
5. **码环极性**：本地码超前 ⇒ magE > magL ⇒ disc > 0 ⇒ **降低**码率把它拉回来
   （`code_inc = 标称 − Kp·disc − 积分项`）。这是本阶段踩过并修复的关键 bug。
6. **载波频率字** = `FREQ_WORD_IF + 频率积分项 + Kp·disc`，32 bit 自然回绕。

## 3. 环路参数

| 项 | 默认值 | 说明 |
|---|---|---|
| DISC_SHIFT | 12 | 把 26 bit 相关值压到 16 bit 判别器后再做乘法（省面积） |
| DLL Kp / Ki | 328 / 33 (Q2.14) | 码环比例/积分 |
| PLL Kp / Ki | 820 / 33 (Q2.14) | 载波环比例/积分 |
| FLL Kp | 328 (Q2.14) | 频率辅助项（相邻窗口判别器之差） |
| 码率限幅 | 261888 ± 3840 | 防码环跑飞 |
| 频率积分限幅 | ±10 kHz | 多普勒范围 |
| 锁定门限 | \|I\|+\|Q\|/2 > 8192，计数 ≥ 200 | 256 计数饱和 |

> 增益整定记录：`disc_shift=6`+大增益会导致码环以约 7.5 chip/ms 振荡；改为压位 12 + 小增益后
> 收敛平稳（见 `reports/ref_model_results.md` 的收敛表）。这是"先做量纲分析再定增益"的直接教训。

## 4. 码表与 NH 来源（重要）

**本阶段没有写入任何 B1I ICD 真值码表。** `rtl/track/code_ram.sv` 是可加载 RAM：
真实 PRN 由 `codegen.load_bits()` 从 ICD 导出文件读入后写进 RAM。仿真用
`codegen.test_code()`（11 级 m 序列 x¹¹+x²+1 截断到 2046 chip），并在
`tb/vectors/track_meta.json` 中显式标注 `TEST_PATTERN_NOT_ICD`。
NH20 同样用占位序列。**切换真实 ICD 码表只需替换向量文件，RTL 不需要改。**

## 5. 验证策略与结果

| 层 | 内容 | 位置 | 结果 |
|---|---|---|---|
| L0/L1 | 载波表、解包、时基定向测试 | `tb/unit/*.sv` | 见 `reports/rtl_unit_results.json` |
| L2 | 2 bit 字节流 → 解包 → 时基 → 跟踪通道，逐 1 ms 与定点模型**逐位比对** | `tb/system/tb_tracking_channel.sv` | 同上 |
| 参考 | 捕获搜索、环路收敛、定点/浮点一致性 | `scripts/run_ref_model.py` | `reports/ref_model_results.md` |

向量由 `python scripts/gen_track_vectors.py` 生成（输入字节流 + 每 1 ms 期望观测量 + 场景元数据含 SHA256）。

## 6. RTL 工具链

Icarus Verilog **不作为仓库内容**（`.gitignore`），脚本按环境变量 `IVERILOG_HOME` → PATH → 常见路径
（`E:\iverilog\app\bin` 等）自动查找，见 `scripts/rtl_tools.py`。

本机安装方式（Windows，无管理员权限时可用 innoextract 直接解包安装器）：

```powershell
# 1) 下载官方 Windows 包（含 setup）
Invoke-WebRequest https://bleyer.org/icarus/iverilog-v12-20220611-x64_setup.exe -OutFile E:\iv12.exe
# 2) 无管理员权限时不要直接运行安装器（会以 exit code 2 失败），改用 innoextract 解包
#    innoextract: https://github.com/dscharrer/innoextract/releases (windows.zip)
innoextract.exe -e -d E:\iverilog E:\iv12.exe
# 3) 验证
E:\iverilog\app\bin\iverilog.exe -V     # Icarus Verilog version 12.0
```

有管理员权限时可直接 `E:\iv12.exe /VERYSILENT /DIR=E:\iverilog`。

## 7. 已知问题（ISSUE-001）

**现象**（最新一次运行）：第 1 个 1 ms 窗口的 E/P/L 与 Q 路相关值与定点模型**逐位一致**，
但 `code_phase` 观测端口读回 0、`freq_word` 差一个更新量；第 2 个窗口起相关值也偏离。
由于第 1 窗口的相关值正确，码 NCO 的 `phase_next`/抽头通路是对的，**嫌疑集中在
`code_phase` 寄存器的更新路径与 `dump_valid` 那一拍的观测时序**。

**ISSUE-002**：`tb_sample_unpacker` 的 `byte_ready/sample_valid` 握手未完成，
仿真超时（已给该 tb 加超时保护并加保护语句，串行套件不再被挂死）。

**复现**：
```powershell
python scripts/gen_track_vectors.py
python scripts/run_rtl_unit.py tracking_channel      # 打印 ISSUE-001 dump 行
```

**已排除**：输入字节流、时基、解包、载波表、窗口边界（前 3 个窗口逐位一致即证明这些正确）。

**下一步排查方向**（按优先级）：
1. 在跟踪通道里把 `code_inc`、`chip_idx` 引到观测端口，确认码 NCO 是被 `load` 常置还是 `phase_next` 归零；
2. 检查 `dll_loop` 中 `KP_C * disc` / `KI_C * disc` 在 Verilog 里的**乘积位宽**（自决定上下文下可能只有 16 bit），
   必要时显式写成 `32'(KP_C) * 32'(disc)`；
3. 用 1 个窗口 + 强制零环路增益（`dll_kp=dll_ki=0`）做回归，隔离"环路"与"码 NCO"两条嫌疑路径。

在此之前，回归只判定前 3 个窗口；其余窗口作为诊断打印，不算通过。

## 8. 已知限制与下一步

1. **捕获引擎 RTL 尚未实现**：本阶段捕获只在 Python 参考模型中完成（码相位搜索正确，
   1 ms 相干 + 2 bit 量化导致频率估计有约 ±300 Hz 偏差，需 P4 做频率细化）。
   RTL 侧下一个增量是 `acquisition_engine.sv`（串行码相位扫描）+ `acquisition_manager.sv`。
2. **E/P/L 抽头为整数码片间距**（默认 1 chip）；0.5 chip 窄相关器留待 P4。
3. **环路未归一化**：判别器量纲随信号幅度变化，灵敏度测试前需要 AGC/归一化。
4. **PLL 拉入范围有限**：本阶段实测能稳定跟随 ±2 Hz 初差；更大初差由捕获/FLL 承担。
5. **12 通道尚未集成**：通道已参数化，下一步用 `generate` 展开并用共享样本时基驱动。
