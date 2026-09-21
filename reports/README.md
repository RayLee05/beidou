# reports/ —— 自动生成的证据

| 路径 | 内容 | 生成者 |
|---|---|---|
| `figures/architecture.png` | 架构总览图 | `scripts/make_architecture_figure.py` |
| `fixed_point_budget.md/.json` | 位宽与周期预算报告 | `scripts/fixed_point_budget.py` |
| `logs/` | `run_all.py` 运行日志（含版本/hash） | `scripts/run_all.py` |

规则：报告头部必须能回答“哪份 RTL/参数、什么时候、用什么工具、什么配置”生成的；
报告与网表/版图/验证报告必须指向同一版本标识。
**这些文件由脚本生成，不要手工编辑**。
