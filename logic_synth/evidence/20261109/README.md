# 2026-11-09 证据索引

- `core_*.rpt`：原三位缓存单通道 TT 实际映射；保持未通过。
- `mapped_outputs_SHA256SUMS`：已下载并校验的原 TT 网表/DDC/SDC；不是修复候选的校验值。
- `rtl_checks.json`、`tb_*.json`：当前二位缓存优化 RTL 回归及源码摘要。
- `pad_connections.txt`、`pad_six_signal.txt`：原三位快照、原厂带电源 PAD 的连接及六星 RTL 验证。
- `probe_gls_*.txt`、`probe_sdf_*.txt`：小探针 SS/FF 门级自检及独立反标日志，均零错误、零告警；不是六路后仿。
- `delay_probe*`：实际 DEL250 延迟单元探针。只对探针额外加严保持不确定度为 1.5 ns，未改变接收机 SDC；经 8 个单元修复到 +0.0753846 ns。未对该加严探针重新做 GLS，不混用此前探针的后仿结论。
- `core_hold_repair_observation.json`：关机前经 SSH 读到的单通道 SS/FF 修复值。新作业完整报告和网表尚未下载、未核对输出 SHA256，不能把该 JSON 当原始完整报告。
- `*_manifest.json`：准确作业目录、输入源码 SHA256、来源与依赖。当前工作区的二位 RTL 与修复作业原三位输入不同，以 manifest 为准。
- `full_baseline_manifest.json` 对应六路中断作业；`hier_pg_probe_manifest.json` 只确认本地打包、未确认上传启动。

`SHA256SUMS` 校验本目录文件。工艺 .db、原厂模型、私钥和大型生成物未加入仓库。完整状态及恢复步骤见 [阶段报告](../../../逻辑综合/逻辑综合报告_20261109.md)。
