# 教师新版输入流适配与验证

更新日期：2026-10-13。新版包：`student_release1/student_release/`。教师原文件保持只读。

## 1 包差异

旧包与新版 `scenario.if2` 均为 409 200 000 字节，SHA256 均为
`2c47d1533fa54316952496ffb7905742c34a989b0a6276b867fe69566c5027da`。
采样率、量化、场景和原始样本没有变化。更新集中于公开流契约、播放器、接口说明、
测试模板和启动脚本；新版模板等待实际 END，提交要求为唯一的 `receiver_records.bin`。

| 项目 | 新版约定 | 已验证旧播放器 |
| --- | --- | --- |
| 每次 32 位握手的样本数 | 16 | 16；旧文档误写为 4 |
| 文件中字节内顺序 | `[7:6]` 最早 | 同左 |
| 流总线顺序 | `[1:0]` 最早至 `[31:30]` 最晚 | 首字节在低 8 位，字节内 `[7:6]` 最早 |
| `sample_index` 步长 | 16 | 4 |
| 接收机模式 | `STREAM_MODE=2, TAG_STRIDE=16` | `STREAM_MODE=1, TAG_STRIDE=4` |

新版播放器将每个文件字节的四组 2 bit 样本重排为低位先行。接收端直接按
`stream_data[2*i +: 2]` 解包，第 i 个样本转换为 −3、−1、+1 或 +3。

## 2 实现更新

- `rtl/common/teacher_stream_frontend.sv`：默认改为新版 16 样本低位先行；保留原播放器及四样本兼容模式。实际样本计数仍由内部单样本握手驱动。
- `rtl/student_receiver_core.sv`：公共顶层默认使用新版模式；自动扫描与 12 通道连接继续使用相同样本语义。
- `scripts/teacher_release.py`：优先定位新版，接受包目录或外层解压目录。公开契约不支持时要求显式选择模式；原旧播放器的纠错适配只应用于已验证源码哈希。
- `scripts/run_teacher_receiver.py`：每次运行先独立检查真实播放器和解包器的组合；模式或编号错误时终止。默认检查至多 65 540 字节，覆盖 64 KiB 缓冲区边界。`--check-stream-only` 检查用户指定的完整区间。
- `tb/integration/tb_teacher_player_order.sv`：按时间顺序从原始文件读取样本作为独立期望，检查每个样本、传输标签、最后标记及背压稳定性。期望值不由流总线重排计算。
- `tb/unit/tb_teacher_stream_frontend.sv`：覆盖三种模式、正常标签、跳号、重复标签、输入停顿、结束及复启动拒绝。
- `probe_teacher_if2.py` 与 `validate_teacher_records.py`：统一选择新版；删除探测脚本中的失效目录路径。

播放器在无 `MAX_BYTES` 且文件长度恰为 64 KiB 整数倍时，仍可能在下一次读文件才发现 EOF，
导致此前最后一拍没有 `stream_last`。仓库运行入口始终传入实际所需字节数，处理该边界。

## 3 验证命令

在项目根目录运行；本机使用 ModelSim SE-64 10.5。

```powershell
python scripts/test_teacher_release.py
python scripts/run_rtl_unit.py teacher_stream_frontend --sim modelsim

# 默认读取新版，检查 65 540 字节的逐样本顺序、结束及公共记录
python scripts/run_teacher_receiver.py --max-bytes 65540 --stall-period 7 `
  --output reports/sim/teacher_v2_smoke.bin --timeout 120

# 外层目录亦可解析；仅做独立采样检查
python scripts/run_teacher_receiver.py --release student_release1 `
  --max-bytes 65540 --check-stream-only

# 显式使用旧包，自动匹配已验证旧播放器
python scripts/run_teacher_receiver.py --release student_release `
  --max-bytes 65540 --stall-period 7 `
  --output reports/sim/teacher_legacy_smoke.bin --timeout 120

python scripts/run_rtl_unit.py --sim modelsim
```

故意把新版配置为旧的字节内解包顺序，应在第一个不匹配样本处失败：

```powershell
python scripts/run_teacher_receiver.py --release student_release1 `
  --stream-mode legacy16 --tag-stride 16 --max-bytes 64 --check-stream-only
```

## 4 已验证范围

新版真实播放器逐样本比较通过：262 160 个样本、16 385 次传输，包含缓冲区跨越。
接收机短流运行的 END 样本总数为 262 160，输入与输出错误标志均为零。
本次短流仅产生 END，用于确认输入适配、样本计数及结束处理；完整 100 s 六星 RTL
信号验收仍需全量运行，不由接口短测代替。

本次验证结果：5 项包选择／契约测试通过；20 项 RTL 回归全部通过；旧版同区间兼容通过，
两版短流 BIN 的 SHA256 均为 `249823d6949ddd0eb6da666087f4a8835cbd2fbaf1716e580c64027462d824e9`。
错误模式在编号 1 的样本（从 0 起计数）处被拒绝，接收机仿真没有启动。
日志位于 `reports/sim/teacher_v2_smoke.*`、`teacher_legacy_smoke.*` 和
`teacher_wrong_mode.stream.log`；完整回归汇总为 `reports/rtl_unit_results.json`。
