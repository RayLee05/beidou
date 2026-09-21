# scripts/ —— 统一运行入口

| 脚本 | 作用 | 关键输出 |
|---|---|---|
| `run_all.py` | 一条命令跑完全部检查 | `reports/logs/run_all-<时间戳>.log` |
| `check_env.py` | 环境与工具链版本盘点 | 控制台 |
| `check_params_consistency.py` | 参数三方一致性（py / svh / json） | 退出码，CI 阻断 |
| `fixed_point_budget.py` | 位宽与周期预算推导与自检 | `reports/fixed_point_budget.{md,json}` |
| `make_architecture_figure.py` | 生成架构总览图 | `reports/figures/architecture.png` |
| `_common.py` | 公共工具（路径、版本、sha256、断言收集） | — |

约定：

- 所有脚本可重复运行、无副作用地覆盖自己的输出。
- 不依赖 pytest（环境未安装）；断言用 `_common.Check`，失败返回非 0 退出码。
- 后续按 `docs/VERIFICATION_PLAN.md` 第 5 节补齐 `run_ref_model`/`run_rtl_unit`/`run_synthesis` 等入口。
