# 六通道逻辑综合工程

本目录为课程六通道综合任务的独立实现，复用原工程的 PRN、跟踪和 NH RTL，不覆盖原十二通道顶层及既有报告。**当前按用户要求暂停。** 六路 RTL 功能基线已通过；已提交的单通道核心预估在展开捕获模块时退出 137，尚无有效面积/时序结果。含真实 PAD 的最终综合、跨角时序、SDF 后仿真和活动功耗尚未完成。

完整计划见 [实施计划](../逻辑综合/实施计划.md)，实际运行结论见 [执行记录](../逻辑综合/执行记录_20261102.md)。

## 核心接口

`bds_bb_6ch_core` 的必需接口为 `clk / rst_n / IF[1:0] / capture_ok[5:0] / bit_sync_ok[5:0] / nav_data[5:0] / nav_valid[5:0]`。时钟为 16.368 MHz，上升沿每拍接收同一个 IF 样本，编码 `00=-3, 01=-1, 10=+1, 11=+3`。所有输出的 bit i 对应第 i 路。

配置口在上升沿同步采样：`cfg_valid=1` 时，`cfg_channel[2:0]` 选择第 0～5 路，原子锁存 `cfg_enable / cfg_prn[5:0] / cfg_dop_min[31:0] / cfg_dop_step[31:0] / cfg_bins[7:0]`。通道编号 6、7 无效。PRN 为 0、bin 数为 0 或 enable 为 0 时停用该路。其余配置使所选路撤销状态，重新装载 PRN 并捕获；其他路继续工作。频率字为有符号 `Hz × 2^32 / 16368000`。外部须提供非负步长，并使搜索范围（含细搜的半步扩展）在跟踪器支持的约 ±10.99 kHz 内。

每路有独立配置、码发生器、捕获缓存、64 路码相位相关器、跟踪环路和 NH 状态。捕获使用两次 1 ms 非相干积分；每路实际存储 33024 个 3 bit 样本。失败时再次捕获；曾锁定后失锁，或 2000 个完整毫秒窗口仍未进入锁定时重新启动。移交追赶每拍最多推进两个相位步，装载时补偿本拍样本，始终不暂停共享 IF。

`capture_ok` 表示当前捕获成功状态，不等同于跟踪已锁定；失锁重启、重配置或停用时撤销。`bit_sync_ok` 表示当前 NH 位同步；`nav_valid` 为新位的单拍脉冲。`nav_data` 已去 NH，保留每路固定的 Costas 整体极性模糊；本接口不输出 BCH 纠错后的子帧。复位低有效，释放须满足库时序；本机激励采用下降沿释放。

## 已执行的 RTL 检查

在仓库根目录运行：

```powershell
python logic_synth/scripts/run_checks.py handover six_channel
python logic_synth/scripts/run_checks.py six_signal
```

脚本复用现有 ModelSim，独立构建到 `build/work`，日志写入 `logs/`。六星端到端测试在当前机器约需 140～160 s。最终通过记录及源文件校验值归档在 [evidence/20261102/](evidence/20261102/)。

| 测试 | 范围 | 结果 |
| --- | --- | --- |
| `tb_handover` | 定向注入移交状态；持续输入/空拍、正负频偏、相位和载波回绕 | 5 个场景通过 |
| `tb_six_channel_control` | 实际六路控制/PRN/NH，注入搜索结果及 Prompt；错时移交、无效通道、生成中改配置、停用/恢复、失锁/重捕获、逐位导航比较 | 通过，数量见原始日志 |
| `tb_six_signal` | 无状态注入的完整两位 IF 链路：PRN 6～11，独立码相位、NH 和电文，六路真实搜索/跟踪/位同步 | 六路均通过，每路 32 位，整体极性每路只确定一次 |

六星信号是软件 PRN 参考生成的无噪声、零多普勒定向场景，经合成和四电平量化。它证明本次六路功能基线，不是教师原始数据、噪声灵敏度、动态频偏或门级时序证据。`sim/prn_reference.hex` 来自 `sw/b1i_ref/prn_b1i.py` 的 PRN 6～11，排列为每颗 2046 行 0/1，测试不读取 DUT 内部码表作真值。

## 核心综合与远端作业

先跑默认单通道，取得面积、未映射对象和资源峰值后再决定六路策略。原 `scripts/vm_remote.py` 无需修改，新客户端沿用其严格主机校验和已有配置，不保存密码或密钥。

```powershell
python logic_synth/scripts/remote.py audit
python logic_synth/scripts/remote.py pack --job core-channel-YYYYMMDD-vN
python logic_synth/scripts/remote.py submit --job core-channel-YYYYMMDD-vN
python logic_synth/scripts/remote.py status --job core-channel-YYYYMMDD-vN
python logic_synth/scripts/remote.py fetch --job core-channel-YYYYMMDD-vN
```

`pack` 固化实际源码与 SHA256，包含未提交修改；远端保持原 RTL 和 `logic_synth/` 的相对结构。`submit` 上传、核验并以 `nohup + setsid` 后台启动，同一作业存在 PID 时只查询，不重复综合。改变源码或脚本须新建作业。SSH 拒绝或断线后可查询；当前远端认证存在间歇故障。

这些是恢复后的操作入口，暂停期间不执行 `submit/start`。已执行 v1 的退出信息和 v2 未提交状态见执行记录。远端脚本后台运行的设计和手工传包备选步骤见 [连接与后台作业说明](../逻辑综合/连接与后台作业.md)。

在远端快照的 `logic_synth/` 内也可直接运行：

```bash
dc_shell -f scripts/synth_core.tcl > logs/core_dc.log 2>&1
```

脚本默认顶层 `bds_channel`，`CORE_TOP=bds_bb_6ch_core` 可选六路核心。使用 TSMC28 TT 库和基本 `compile`，输出 `output/core_<top>/baseline.v / baseline.ddc / exploratory.sdc`，及 `reports/core_<top>/` 的面积、setup/hold、约束、库和环境报告。`job.sh` 记录 `/usr/bin/time -v` 资源和退出码。TT 的 min/max 路径只是核心诊断，不代表 SS/FF 验收。

`core_exploration.sdc` 使用标明的临时核心引脚预算，不是最终外部 PAD 约束。当前脚本报告库默认的工作条件与连线模型；正式阶段须从报告核对并冻结。`CORE_MAPPING_DONE` 只说明脚本执行到实际映射检查，时序/黑盒/设计规则仍须审核原始报告。

## 含 PAD 的后续工作

真实 PAD `.db`、标准单元与 PAD 的时序 Verilog、控制脚和 PVT 配对确认前，不创建假 PAD 顶层，也不生成 `final.*`。`scripts/synth.tcl` 当前显式退出并提示所缺条件；它是正式入口的阻塞提示，尚不是完成的正式综合流程。

配套资料齐全后，依计划 M4～M6 完成真实封装、正式约束与优化流程，提供 `sim/tb.sv` 的 `tb.dut`、仅含门级设计的 `sim/gls.f`，同次导出 `output/final.v/.ddc/.sdc` 及两种工艺条件的 SDF。现有 `scripts/power.tcl` 只预备了按固定路径恢复 DDC 和 SAIF 的入口，须随正式库和流程一并验证；它不会自行重新综合或覆盖活动。`reports/gls_accepted.txt` 只能在真实后仿真通过且证据核查后生成。

工艺 `.db/.lib`、原始模型、版图资料、凭据均不放入 Git。生成日志和网表保留在本机或受控实验室目录；公开交付前按课程许可要求处理。
