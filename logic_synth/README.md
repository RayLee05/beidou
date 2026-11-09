# 六通道逻辑综合工程

本目录为课程六通道综合任务的独立实现，复用原工程的 PRN、跟踪和 NH RTL，不覆盖原十二通道顶层及既有报告。**2026-11-09 恢复后，16:16 用户确认虚拟机关闭，完整作业中断。** 六路 RTL 功能基线已通过；原单路 TT 映射面积 442453.66，保持未通过；新 SS/FF 单路延迟修复候选时序与约束违例为 0、面积 876538.79，完整文件待恢复后取回校验。真实 PAD 时序库和带电源模型已部署，小探针 SS/FF 后仿反标零错误、零告警；完整六路最终时序、后仿和功耗未完成。最新状态见 [11 月 9 日执行记录](../逻辑综合/执行记录_20261109.md)。

完整计划见 [实施计划](../逻辑综合/实施计划.md)，本次测量及验收状态见 [综合报告](../逻辑综合/逻辑综合报告_20261109.md)，历史结果见 [11 月 2 日记录](../逻辑综合/执行记录_20261102.md)。

## 核心接口

`bds_bb_6ch_core` 的必需接口为 `clk / rst_n / IF[1:0] / capture_ok[5:0] / bit_sync_ok[5:0] / nav_data[5:0] / nav_valid[5:0]`。时钟为 16.368 MHz，上升沿每拍接收同一个 IF 样本，编码 `00=-3, 01=-1, 10=+1, 11=+3`。所有输出的 bit i 对应第 i 路。

配置口在上升沿同步采样：`cfg_valid=1` 时，`cfg_channel[2:0]` 选择第 0～5 路，原子锁存 `cfg_enable / cfg_prn[5:0] / cfg_dop_min[31:0] / cfg_dop_step[31:0] / cfg_bins[7:0]`。通道编号 6、7 无效。PRN 为 0、bin 数为 0 或 enable 为 0 时停用该路。其余配置使所选路撤销状态，重新装载 PRN 并捕获；其他路继续工作。频率字为有符号 `Hz × 2^32 / 16368000`。外部须提供非负步长，并使搜索范围（含细搜的半步扩展）在跟踪器支持的约 ±10.99 kHz 内。

每路有独立配置、码发生器、捕获缓存、64 路码相位相关器、跟踪环路和 NH 状态。捕获使用两次 1 ms 非相干积分；当前工程每路存储 33024 个 2 bit 四电平样本，回放时无损恢复为 3 bit。已经映射的原基线仍为三位缓存，结果分别记录。失败时再次捕获；曾锁定后失锁，或 2000 个完整毫秒窗口仍未进入锁定时重新启动。移交追赶每拍最多推进两个相位步，装载时补偿本拍样本，始终不暂停共享 IF。

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

`pack` 固化实际源码与 SHA256，包含未提交修改；远端保持原 RTL 和 `logic_synth/` 的相对结构。`submit` 上传、核验并以 `nohup + setsid` 后台启动，同一作业存在 PID 时只查询，不重复综合。改变源码或脚本须新建作业。当前采用用户更新的 NAT SSH 路由；先前桥接路由的间歇故障作为历史记录保留。

这些是恢复后的操作入口。远端脚本后台运行的设计和手工传包备选步骤见 [连接与后台作业说明](../逻辑综合/连接与后台作业.md)。

在远端快照的 `logic_synth/` 内也可直接运行：

```bash
dc_shell -f scripts/synth_core.tcl > logs/core_dc.log 2>&1
```

脚本默认顶层 `bds_channel`，`CORE_TOP=bds_bb_6ch_core` 可选六路核心。使用 TSMC28 TT 库和基本 `compile`，输出 `output/core_<top>/baseline.v / baseline.ddc / exploratory.sdc`，及 `reports/core_<top>/` 的面积、setup/hold、约束、库和环境报告。`job.sh` 记录 `/usr/bin/time -v` 资源和退出码。TT 的 min/max 路径只是核心诊断，不代表 SS/FF 验收。

`core_exploration.sdc` 使用标明的临时核心引脚预算，不是最终外部 PAD 约束。当前脚本报告库默认的工作条件与连线模型；正式阶段须从报告核对并冻结。`CORE_MAPPING_DONE` 只说明脚本执行到实际映射检查，时序/黑盒/设计规则仍须审核原始报告。

## 当前含 PAD 流程与边界

真实 PAD 库、带电源模型、111 位 PAD 顶层、UPF 和门级文件清单已加入。`scripts/synth.tcl` 为分层候选流程，复用完成的映射单路；`candidate.*` 只供审查，不自动认定最终通过。最新完整六路作业的 UPF/PG 集成尚未完成。

使用 `--base-job` 及 `--base-rtl` 可将基线单路的准确 RTL 从原快照取入新包，并核对校验值；`--ss-checkpoint-job` 可复用同一基线已完成的 SS 绑定检查点。这些机制避免将当前二位优化源码与旧三位 DDC 混为同一次综合。

原单路 TT 的网表、DDC、SDC 已下载到 `reports/remote/core-channel-20261109-v1/results/logic_synth/output/core_bds_channel/`，并核对远端 SHA256。原始及精简报告见 [本次执行记录](../逻辑综合/执行记录_20261109.md) 和 `evidence/20261109/`。

`sim/tb.sv` 使用模块 tb、实例 dut，包含真实六星激励及仅在 GLS 模式启用的反标/VCD。门级模型采用带电源视图；VCS 2014 需核对 `-negdelay +neg_tchk +define+NTC+RECREM` 和匹配的 SDF 3.0，逐项审查独立反标日志。小探针或 RTL 的 PASS 不代表完整六路后仿通过。

当前无完成验收的 `final.v/final.ddc/final.sdc/final_*.sdf` 或六路活动功耗。`power.tcl` 仍需最终同版 DDC/SDC、已审核 GLS 和真实 SAIF 才能运行；不以默认活动替代。

工艺库、原始模型与凭据不纳入 Git，运行生成物保留在受控目录。物理 Bond Pad、PG 版图及真实寄生签核属于后续阶段。
