# 项目文档索引

给接手编码的 AI 的入口是 [`AI_HANDOFF.md`](AI_HANDOFF.md)；
给组内成员的第一入口是 [`PLAN.md`](PLAN.md)（分工、学时、里程碑）。

| 文件 | 用途 | 阶段 |
|---|---|---|
| `AI_HANDOFF.md` | 交接目标、执行顺序、完成定义、必须先确认的问题 | 全程 |
| `requirements.md` | **需求清单**：73 条分族编号需求、来源、优先级、追踪矩阵、待确认表 | P0 |
| `PLAN.md` | **组内计划**：角色分工、72 学时映射、里程碑出口条件、风险、AI 核验规则 | P0 |
| `ARCHITECTURE.md` | 架构：数据流、RTL/软件分层、状态机、实现取舍 | P0/P1 |
| `INTERFACES.md` | 接口契约：输入 metadata、顶层端口、记录 schema、配置、RINEX、软件 API、错误码 | P0/P1 |
| `FIXED_POINT.md` | **位宽与周期预算**：定点论证、累加器推导、时基/伪距分辨率、资源取舍 | P1 |
| `VERIFICATION_PLAN.md` | 分层验证、验收矩阵、断言、里程碑、运行入口、风险 | 全程 |
| `status.md` | 当前进度、本轮证据路径、下一轮任务 | 全程 |

## 相关产物（不在本目录）

| 产物 | 位置 | 生成者 |
|---|---|---|
| 架构总览图 | `../reports/figures/architecture.png` | `scripts/make_architecture_figure.py` |
| 位宽与周期预算报告 | `../reports/fixed_point_budget.md` | `scripts/fixed_point_budget.py` |
| 运行日志 | `../reports/logs/` | `scripts/run_all.py` |
| 参数单一来源 | `../sw/b1i_ref/params.py` ↔ `../rtl/include/b1i_params.svh` | — |

根目录两份 PDF 仍是需求原始来源（课程安排 + 基带与位置解算基础），实现时以**正式 B1I ICD 与教师冻结的课程基线**为准。

> 注意：这两份 PDF 与 `VM-IC-SSH连接指南.md` **不入公开仓库**（见根目录 `.gitignore` 与 `README.md` 的“仓库范围说明”）。

## 文档维护规则

1. 需求变更：先改 `requirements.md`（新条目或版本记录），再改代码。
2. 接口变更：`INTERFACES.md` 必须同步版本号与回归向量。
3. 参数变更：只改 `params.py`，再同步 `b1i_params.svh` 与配置，最后跑 `scripts/run_all.py`。
4. 每阶段结束把实际命令与证据路径写入 `status.md`。
