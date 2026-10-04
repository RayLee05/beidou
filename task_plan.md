# 任务计划：本机能做的验证全部做完并落证据

## 目标
在本机（ModelSim / Python，不依赖 IC 虚拟机）把还能完成的功能验证跑完，并把命令、结果写入文档。不提交、不推送。

## 当前阶段
阶段 10 已完成。审查项里本机能改的已落地并复测。不提交、不推送。

## 各阶段

### 阶段 1–5：RTL 顶层与快测
- **状态：** complete

### 阶段 6：本机长测与记录
- **状态：** complete

### 阶段 7：任务与代码详细审查
- **状态：** complete

### 阶段 8：修复 P1
- [x] 测量伪距 / RINEX 时间基准
- [x] BCH 拒识 + STATUS
- [x] 同步超时
- [x] 事件队列
- [x] 回写过时文档
- **状态：** complete
- **证据：** `run_local_chain` |Δr|=35.1 m，钟差 119.96 µs

### 阶段 9：本机还能做的 P2 / 记录闭环
- [x] `rec_last`、FIFO 深度/满时读写、`error_code` 与 EV_OVERFLOW 对齐
- [x] 256 bit 打包/回读 + hex → PVT
- [x] generation 过滤 + RINEX 独立校验
- [x] 清 16384 / 架构图用词
- [x] ModelSim 快测 + 软件自检
- **状态：** complete

### 阶段 10：二次审查后的本机修复
- [x] RTL：历元包不插队、EPOCH 冻结、FIFO 回压、tx+1、code_phase=`ds<<18`、cfg `sow0_ms`
- [x] 软件：OBS/PVT 用 `sow0_ms`、`refine_sagnac`、FFT+短跟踪移交
- [x] `.gitignore` 本机 xsim/webtalk
- [x] ModelSim 快测 8/8、`tb_b1i_rx_top`、`check_records`、7 s×4 链路
- **状态：** complete
- **证据：** |Δr|=35.125 m，dt=119.96 µs；移交不再用真值半码片

## 已做决策
| 决策 | 理由 |
|------|------|
| 证据写入 docs/ 与 reports/ | 下次接着测不用翻聊天记录 |
| 不跑 7 s RTL 全链路 | ModelSim 墙钟不可接受；记录闭环用打包 hex + 软件 PVT |
| 不提交不推送 | 用户明确禁止上传代码 |

## 遇到的错误
| 错误 | 尝试次数 | 解决方案 |
|------|---------|---------|
| local_chain 701 km | 2 | 精细距离用 sample_end，dump 结束 +1 ms |
