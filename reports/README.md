# reports/ —— 自动生成的证据

| 路径 | 内容 | 生成者 |
|---|---|---|
| `figures/architecture.png` | 架构总览图 | `scripts/make_architecture_figure.py` |
| `fixed_point_budget.md/.json` | 位宽与周期预算报告 | `scripts/fixed_point_budget.py` |
| `logs/` | `run_all.py` 运行日志（含版本/hash）；**只保留最近 5 次**，更早的由脚本自动清理 | `scripts/run_all.py` |

规则：报告头部必须能回答“哪份 RTL/参数、什么时候、用什么工具、什么配置”生成的；
报告与网表/版图/验证报告必须指向同一版本标识。
**这些文件由脚本生成，不要手工编辑**。

## 2026-10-13 报告证据入口

当前四份提交报告在 `deliverables/模块实验报告/` 与 `deliverables/总体架构方案/`。
`deliverables/模块实验报告/验证资料_20261013/` 保存本次 20 项 RTL、独立播放器排列、短流 END 和教师 NAV 校验证据；原图表与软件复核资料保留在 `验证资料_20261012/`。
当前架构图以流式教师入口为主，另保留可编辑 SVG。自动预算只覆盖脚本实现的项目，完整 48 位码 NCO 与 D1 元数据状态容量见 `docs/FIXED_POINT.md`，不能据自动预算推定最终综合面积。
