# -*- coding: utf-8 -*-
"""生成《北斗 B1I 基带处理器 总体架构方案》的 Markdown 与 DOCX。

内容经过 humanizer-zh 处理：去掉夸张意义、三段式、破折号堆叠、AI 高频词，
改用直接陈述与具体数字。排版按任务书要求：
  子标题 四号(14pt) 加粗；正文 小四(12pt) 宋体、行距固定 22 磅、首行缩进 2 字符；
  表头 五号(10.5pt) 加粗；图下标注 五号(10.5pt) 加粗居中。
用法: python scripts/build_arch_report.py
"""
from __future__ import annotations
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "deliverables", "总体架构方案")
FIG = os.path.join(ROOT, "reports", "figures", "architecture.png")
BT = chr(96)

T_NO = "（待定）"

DOC = [
("h1", "北斗 B1I 基带信号处理器总体架构方案"),
("p", "版本 v1.1　2026-09-27　课程：北斗B1I基带处理与电文解调 ASIC 设计实践（72 学时，2 人一组）"),
("p", "本文说明这颗基带处理器的输入输出、总体架构、模块划分、模块间信号和控制器状态机。"
      "参数取自实验指导书与 B1I ICD，凡指导书未给出的量，一律留待配套发布清单，不自行填数。"),

("h2", "0　文档依据与参数基线"),
("table", [["项", "值", "依据"],
 ["中频 fIF", "4.092 MHz", "实验指导书 2.3 节，fIF = Fs/4"],
 ["采样率 Fs", "16.368 MHz", "指导书 2.3 节：每码片 8 样本，Fs = 8 × 2.046 MHz"],
 ["1 ms 样本数", "16368", "2046 chip × 8 样本/chip"],
 ["量化", "2 bit/样本，00=-3、01=-1、10=+1、11=+3", "指导书 1.2 节"],
 ["测距码", "2.046 Mcps，2046 chip/ms，平衡 Gold 码截短 1 码片", "ICD 2.1 第 4.3 节"],
 ["二次码", "NH20 = 00000100110101001110，1 ms/比特", "ICD 2.1 第 5.2.1 节"],
 ["电文", "D1，50 bps；子帧 300 bit/6 s；主帧 1500 bit/30 s", "ICD 2.1 第 5.2.2 节"],
 ["纠错", "BCH(15,11,1)，g(X)=X⁴+X+1，两组交织成 30 bit", "ICD 2.1 第 5.1.3 节"],
 ["通道数", "12 个逻辑通道，共用样本流和时基", "课程安排 P5、P11"],
 ["目标时钟", T_NO, "指导书 12.1 节：从配套发布清单读取，缺失就报告缺失"]]),
("caption", "表 1　参数基线"),

("h2", "1　系统输入输出定义"),
("h3", "1.1　输入"),
("table", [["输入项", "形式", "字段", "来源与约束"],
 ["SRAM 采样数据", "同步 SRAM 读接口", "读地址、读使能、读数据；内部取样有效 sample_valid", "字宽、地址单位、读延迟、样本总数由配套清单给出"],
 ["场景配置", "配置寄存器", "候选 PRN 集合、噪声种子、每星 C/N0、动态类别", "候选 PRN 集合可以作搜索输入，真实可见星清单只给评估"],
 ["搜索配置", "配置寄存器", "多普勒起止与步长、码相位步长、相干与非相干时长、门限", "门限形式与数值随任务书冻结"],
 ["跟踪配置", "配置寄存器", "DLL、FLL、PLL 系数，失锁超时，锁定门限", "位宽与量纲见位宽与周期预算"],
 ["输出配置", "配置寄存器", "历元间隔、记录使能、debug 使能", "历元间隔默认 1 s"],
 ["时钟与复位", "端口", "clk、rst_n", "目标频率从配套清单读取"]]),
("caption", "表 2　系统输入"),
("h3", "1.2　输出"),
("table", [["输出项", "内容", "关键字段", "有效性规则"],
 ["obs 观测记录", "每个公共历元、每颗卫星一条", "公共历元、PRN、channel_id、generation、整数码周期、分数码相位、多普勒、载噪比、measurement_valid、可用时刻", "未锁定或没有时间锚点时 measurement_valid=0，字段置无效。不拿真值或 0 顶替"],
 ["nav 导航记录", "解调出的 D1 电文参数", "PRN、bit_start_sample、subframe_id、BDT 时间、星历、钟差、健康、decode_valid、BCH 状态", "校验失败或未同步时 decode_valid=0"],
 ["status 状态事件", "通道状态迁移与异常", "channel_id、generation、状态前后值、失锁原因、发生时刻、overflow 与 timeout 标志", "事件必须能被观察到，不允许静默恢复"]]),
("caption", "表 3　系统输出"),
("h3", "1.3　边界与真值隔离"),
("p", "指导书 12.1 节把评估真值和算法输入分开：完整 PRN 候选集合可以给捕获搜索，"
      "实际可见星清单、真实码相位、频偏和传播时延只能给评估程序。"
      "接口文档里要标明哪些字段属于评估专用。"),
("p", "RTL 只输出结构化记录，不拼 RINEX 文本。OBS 和 NAV 由配套适配器生成。"),

("h2", "2　架构设计"),
("h3", "2.1　总体数据流"),
("figure", "图 1　北斗 B1I 基带处理器总体架构"),
("p", "样本从 SRAM 读出后进入解包和公共时基。时基同时喂给后台捕获引擎和 12 个跟踪通道。"
      "跟踪通道每毫秒交出一组 E/P/L 复相关值，一半送给环路和位同步，一路交给测量生成。"
      "同步解调部分完成 NH 去二次码、子帧同步、去交织和 BCH 译码，恢复出星历、钟差和健康字段。"
      "测量生成把整数码周期、分数码相位和电文时间锚点拼到一起，历元聚合再按公共历元把多星记录排好，"
      "最后经 FIFO 输出给配套适配器。"),
("h3", "2.2　分层与职责"),
("table", [["层", "职责", "不做什么"],
 ["取数与时基层", "SRAM 读时序、2 bit 解包、样本编号、1 ms 与 20 ms 等边界", "不做相关，不做控制决策"],
 ["捕获层", "搜索任务调度、码相位与多普勒假设、检测判决、向通道移交初值", "不做持续跟踪"],
 ["跟踪层", "载波与码 NCO、混频、E/P/L 相关、DLL 与 FLL/PLL、锁定与失锁判断", "不做电文解析"],
 ["同步与解调层", "NH 去二次码、位同步、子帧同步、去交织、BCH、字段提取", "不做测量聚合"],
 ["测量与输出层", "整周期加分数码相位、时间锚点、历元聚合、有效性裁决、记录输出", "不做浮点定位，不拼文本"],
 ["控制与配置层", "顶层状态机、通道分配、重捕获、配置寄存器、错误上报", "不进入数据通路"]]),
("caption", "表 4　分层与职责"),
("h3", "2.3　关键架构决策"),
("table", [["#", "决策", "理由"],
 ["D1", "输入按配套 SRAM 同步读接口设计，不按文件字节流", "指导书 1.3 节给出字宽、读延迟和样本总数都由配套清单决定，接口必须照清单做"],
 ["D2", "12 通道全并行，每通道独立 NCO、相关和环路状态", "1 样本/时钟时通道占空比约 16%，复用省下的乘法器会被多端口累加器吃掉；全并行也便于逐通道定位故障"],
 ["D3", "捕获与跟踪复用同一套混频、NCO 和相关结构", "指导书 2.8 和 4.6 节要求核算后台捕获与 12 通道并发时的读写冲突和存储带宽"],
 ["D4", "载波 sin/cos 表全芯片一份共享只读 ROM", "每通道一份要 12 份 ROM，共享后 ROM 面积降到约 1/12"],
 ["D5", "相关、状态和测量记录都带 generation 字段", "失锁重捕获后旧代次数据不能被误用（指导书表 2-2）"],
 ["D6", "模块间用 ready/valid 握手，未接纳的数据和标签保持稳定", "指导书 2.8 节的要求；跨时钟域多位信息要保证字一致性"],
 ["D7", "环路在 1 ms 窗口边界更新，并用旁路让新窗口第一个样本就用新系数", "窗口内 16368 个样本共用一组系数，便于和定点模型逐位对齐"]]),
("caption", "表 5　关键架构决策"),
("h3", "2.4　资源与周期预算摘要"),
("table", [["项", "值", "说明"],
 ["每样本关键运算", "12 通道共约 132 次定点运算/样本", "混频 2 次，累加 6 次，码抽头 3 次"],
 ["基准乘法器", "24 个，每通道 2 个混频乘", "393 MMAC/s；复用方案见位宽与周期预算第 8 节"],
 ["1 ms 相干累加位宽", "26 bit，E/P/L 各 I/Q 共 6 路", "最坏情况 16368×3×512 = 25141248"],
 ["20 ms 合并位宽", "需要 30 bit，实配 32 bit", "最坏情况 502824960"],
 ["NCO 相位位宽", "32 bit", "IF 与码率都能精确表示，没有截断误差"],
 ["时基回绕", "SAMPLE_INDEX 32 bit，262.4 s", "覆盖一个 30 s 主帧还绰绰有余"]]),
("caption", "表 6　资源与周期预算摘要"),

("h2", "3　模块划分"),
("table", [["模块", "职责", "所属接口组", "需求"],
 ["sram_reader", "SRAM 读时序与样本解包", "SRAM 采样", "REQ-IN-000"],
 ["sample_timebase", "样本编号与 1 ms、20 ms、6 s、1 s 边界", "SRAM 采样", "REQ-TB-001..004"],
 ["carrier_lut", "载波 sin/cos 只读表，全芯片共享", "—", "REQ-TRK-002"],
 ["carrier_mixer_nco", "载波 NCO 与 I/Q 混频", "correlator_result 前级", "REQ-TRK-002"],
 ["code_nco", "码相位 NCO（Q11.21）与码周期回绕", "—", "REQ-TRK-002"],
 ["code_ram", "PRN 码存储与 E/P/L 三抽头", "—", "REQ-SIG-006"],
 ["correlator_epl", "E/P/L 六路 1 ms 相干累加与窗口转存", "correlator_result", "REQ-TRK-002"],
 ["dll_loop", "码环鉴别与二阶滤波", "correlator_result 到环路", "REQ-TRK-003"],
 ["fll_pll_loop", "Costas 鉴相、二阶 PLL、FLL 辅助、锁定判决", "correlator_result 到环路", "REQ-TRK-003/004"],
 ["tracking_channel", "单通道集成，参数化复制为 12 路", "channel_status", "REQ-TRK-001/005"],
 ["acquisition_engine", "码相位与多普勒假设的串行搜索与判决", "search_req、search_result", "REQ-ACQ-001..006"],
 ["acquisition_manager", "搜索任务调度、资源仲裁、峰值判决与移交", "search_req、allocate", "REQ-ACQ-004"],
 ["channel_manager", "PRN 到通道的分配、状态机、重捕获、代次管理", "allocate、init、recover、cancel", "REQ-TRK-001/004"],
 ["nh_sync", "去 NH20、位同步、位起点时标", "correlator_result 到同步", "REQ-SYN-001/002"],
 ["d1_frame_sync", "子帧同步、去交织、BCH", "—", "REQ-SYN-003/004"],
 ["nav_decoder", "时间、星历、钟差、健康字段提取", "obs、nav", "REQ-NAV-001..003"],
 ["measurement_engine", "码相位、整周期、时间锚点合成伪距输入", "obs、nav", "REQ-MEAS-001/002"],
 ["epoch_aggregator", "公共历元聚合与有效性裁决", "obs、nav", "REQ-MEAS-003/004"],
 ["record_fifo", "结构化记录输出与背压", "obs、nav", "REQ-OUT-001..003"],
 ["b1i_rx_top", "顶层互联、配置寄存器、错误上报", "全部", "REQ-IMPL-002"]]),
("caption", "表 7　模块划分"),

("h2", "4　各模块关键信号"),
("h3", "4.1　模块间接口组（按指导书表 2-2）"),
("table", [["接口组", "方向", "关键字段", "传输行为"],
 ["SRAM 采样", "存储到输入处理", "读地址、读使能、读数据；内部 sample_valid", "固定读延迟，取样有效只在数据有效时置位"],
 ["search_req", "管理到捕获", "PRN、task_id、搜索范围、积分配置、窗口参考", "ready/valid，未接纳时保持稳定"],
 ["search_result", "捕获到管理", "成败、PRN、task_id、码相位、频偏、参考时刻、质量", "单拍结果，带 task_id 便于匹配"],
 ["allocate 与 init", "管理及控制到通道", "channel_id、generation、PRN、初值、生效时刻", "同拍生效，未接纳要重发"],
 ["correlator_result", "相关器到环路与同步", "E/P/L 复相关 I/Q、窗口完成、本地参考约定、PRN、generation", "每 1 ms 一次窗口完成脉冲"],
 ["channel_status", "通道到控制与管理", "分层有效位、质量、失锁原因、发生时刻", "事件式，脉冲突发"],
 ["recover 与 cancel", "控制与管理之间", "任务身份、最后估计、重试次数、取消原因", "握手确认"],
 ["obs 与 nav", "通道到输出", "公共历元、测量或参数、有效位、身份、可用时刻", "FIFO 加 ready/valid，溢出可观察"]]),
("caption", "表 8　模块间接口组"),
("h3", "4.2　顶层关键端口"),
("table", [["端口", "方向", "位宽", "说明"],
 ["clk、rst_n", "in", "1", "统一时钟，异步复位同步释放"],
 ["sram_addr、sram_en、sram_rdata", "out/in", "按配套清单", "SRAM 读接口"],
 ["sample_valid、sample", "内部", "1、3 signed", "解包后的取样有效与幅度"],
 ["cfg_valid、cfg_addr、cfg_wdata、cfg_ready", "in/out", "1、32、32、1", "配置写入与读回"],
 ["rec_valid、rec_ready、rec_data、rec_last", "out/in", "1、1、256、1", "结构化记录输出"],
 ["ch_locked、ch_bit_valid、ch_nav_valid", "out", "各 12 位", "通道分层有效位"],
 ["error_valid、error_code", "out", "1、32", "错误上报，不静默"]]),
("caption", "表 9　顶层关键端口"),
("h3", "4.3　跟踪通道内部关键信号"),
("table", [["信号", "位宽", "含义"],
 ["freq_word", "32 signed", "载波频率字 = IF 字 + 多普勒，直接驱动载波 NCO"],
 ["carrier_phase", "32", "载波相位累加器，模 2³² 回绕"],
 ["mix_i、mix_q", "13 signed", "样本乘 cos 与负样本乘 sin，全精度不截位"],
 ["code_phase", "32", "Q(11.21)，整数码片 [31:21] 加小数码片 [20:0]"],
 ["code_inc", "32 signed", "码率增量，标称 262144 = 2²¹/8"],
 ["chip_idx", "11", "当前码片索引，0 到 2045"],
 ["e_tap、p_tap、l_tap", "1", "E/P/L 三抽头码值"],
 ["i_e、q_e、i_p、q_p、i_l、q_l", "26 signed", "1 ms 相干累加结果，窗口完成时转存"],
 ["dump_valid", "1", "窗口完成脉冲，与新窗口第一个样本同拍"],
 ["dll_disc、pll_disc", "16 signed", "压位后的码环与载波环鉴别器，用于观测"],
 ["locked", "1", "幅值过门限并维持足够计数后置位"]]),
("caption", "表 10　跟踪通道内部关键信号"),

("h2", "5　控制器状态机"),
("h3", "5.1　顶层控制状态机"),
("code", "RESET -> IDLE -> CONFIG -> RUN_SINGLE -> RUN_MULTI -> DONE\n                              |            |\n                              v            v\n                           ERROR <----- ABORT"),
("table", [["当前状态", "条件", "次态", "动作"],
 ["RESET", "rst_n 释放且配置校验通过", "IDLE", "清所有 valid，读回配置"],
 ["IDLE", "收到启动且通道分配有效", "CONFIG", "下发 allocate 与 init，装载 PRN 码表"],
 ["CONFIG", "12 通道 init 完成", "RUN_SINGLE", "启动公共时基，放开样本取样"],
 ["RUN_SINGLE", "首个公共历元完成", "RUN_MULTI", "打开后台捕获与多星聚合"],
 ["RUN_MULTI", "样本耗尽或主机停止", "DONE", "冲刷 FIFO，输出末历元"],
 ["任意", "FIFO 溢出、配置越界、格式错误", "ERROR", "置 error_code，撤销所有有效测量"],
 ["ERROR", "复位", "RESET", "错误码保持可读"]]),
("caption", "表 11　顶层控制状态机"),
("h3", "5.2　跟踪通道状态机"),
("code", "RESET -> IDLE -> ACQUIRE -> TRACK_PULL_IN -> TRACK_LOCKED\n                        ^                |              |\n                        |                v              v\n                    REACQUIRE <-------- LOST <---- BIT_SYNC\n                                                       |\n                                                       v\n                                          FRAME_SYNC -> NAV_VALID"),
("table", [["状态", "进入条件", "退出条件", "输出有效位"],
 ["IDLE", "复位或取消", "收到 allocate 与 init", "全部为 0"],
 ["ACQUIRE", "已分配 PRN 与搜索范围", "捕获成功且质量达标，或超时", "成功时 acquired=1"],
 ["TRACK_PULL_IN", "收到初值", "锁定计数达标，或超时", "locked=0"],
 ["TRACK_LOCKED", "锁定计数达标", "幅值或频率超限", "locked=1"],
 ["BIT_SYNC", "累加 NH20 相关", "位边界置信度达标，或超时", "bit_valid=1"],
 ["FRAME_SYNC", "位流连续", "子帧头匹配", "frame_valid=1"],
 ["NAV_VALID", "子帧译码且 BCH 通过", "失锁，或校验连续失败", "nav_valid=1"],
 ["LOST", "锁定计数归零或超时", "重捕获计时到", "有效位清零，撤销本代次测量"],
 ["REACQUIRE", "重捕获计时到", "重新分配", "generation 自增，旧代次数据作废"]]),
("caption", "表 12　跟踪通道状态机"),
("h3", "5.3　捕获引擎状态机"),
("code", "IDLE -> LOAD_HYP -> INTEGRATE(1 ms) -> EVALUATE -> (还有假设? LOAD_HYP : DONE)\n                                                              |\n                                                              v\n                                                        REPORT(峰值/门限)"),
("table", [["状态", "动作", "时序"],
 ["IDLE", "等待 search_req", "—"],
 ["LOAD_HYP", "装载码相位初值与载波初相，清累加器", "1 拍"],
 ["INTEGRATE", "累加 16368 个样本", "16368 个 sample_valid"],
 ["EVALUATE", "算 I²+Q² 或 |I|+|Q|/2，与当前峰值和门限比较", "1 拍"],
 ["SWEEP", "推进到下一个假设，码相位步进满了就进多普勒位", "1 拍"],
 ["REPORT", "输出 search_result，含成败、码相位、频偏、质量", "握手 1 拍"]]),
("caption", "表 13　捕获引擎状态机"),
("h3", "5.4　相关器窗口时序"),
("table", [["时刻", "事件", "说明"],
 ["窗口第 1 到第 16367 个样本", "累加", "使用本窗口固定的一组系数"],
 ["窗口最后 1 个样本", "ms_tick", "连同本样本一起转存 dump，累加器清零"],
 ["下一拍，新窗口第 1 个样本", "dump_valid", "环路完成更新并旁路生效，新窗口立即用新系数"],
 ["每 20 个 ms_tick", "bit_boundary", "一个 D1 数据位边界"],
 ["每 300 个数据位", "subframe_boundary", "子帧边界，6 s"],
 ["每 1000 ms", "epoch_boundary", "公共输出历元"]]),
("caption", "表 14　相关器窗口时序"),
("h3", "5.5　复位与异常"),
("p", "复位采用异步复位、同步释放。复位后所有 valid 为 0，0 不当合法测量使用。"),
("p", "失锁、超时、校验失败都要置错误码并撤销当前有效测量，不能输出看着有效的假数据。"),
("p", "计数器回绕是定义好的行为，不产生负时间，也不重复历元。"),
("p", "ready/valid 未接纳时数据与标签保持稳定，FIFO 溢出必须能被观察到。"),

("h2", "6　接口规范模板"),
("p", "以 correlator_result 为例，按指导书 12.2 节逐项写清。"),
("table", [["项", "内容"],
 ["模块名称", "correlator_epl"],
 ["输入", "mix_i 与 mix_q（13 bit signed）、e/p/l_tap（1 bit）、sample_valid、ms_tick"],
 ["输出", "dump_i_e、dump_q_e、dump_i_p、dump_q_p、dump_i_l、dump_q_l（26 bit signed），dump_valid"],
 ["数值含义", "有符号补码，1 ms 相干累加，最坏绝对值 16368×3×512 = 25141248，26 bit 刚好覆盖"],
 ["更新条件", "sample_valid 有效时累加，ms_tick 时转存并清零"],
 ["复位值", "累加器全 0，dump_valid 为 0"],
 ["异常行为", "位宽按最坏情况推导，累加器不会上溢或下溢；输入越界由上游错误码捕获"]]),
("caption", "表 15　接口规范模板"),

("h2", "7　验证与验收对应"),
("table", [["架构要素", "验证方式", "证据"],
 ["SRAM 取数与解包", "定向向量加波形", "tb/unit/tb_sample_unpacker.sv"],
 ["公共时基边界", "1 ms、20 ms、6 s、1 s 计数断言", "tb/unit/tb_sample_timebase.sv"],
 ["载波表", "四象限定点值比对", "tb/unit/tb_carrier_lut.sv"],
 ["单通道跟踪链路", "与定点参考模型逐 1 ms 比对", "tb/system/tb_tracking_channel.sv"],
 ["捕获搜索", "与 FFT 圆相关参考比对码相位和频偏", "sw/b1i_ref/acquisition.py"],
 ["12 通道无丢样", "吞吐计数与 SRAM 读带宽证据", "待实现"],
 ["OBS 与 NAV 有效性", "RINEX 往返读取，缺测不伪造", "待实现"]]),
("caption", "表 16　验证与验收对应"),

("h2", "8　架构补充分析"),
("p", "这一章补四件事：SRAM 读带宽够不够用、捕获和跟踪怎么分硬件、12 通道大概占多少资源、"
      "以及通道状态机的编码和超时值。数字都按第 0 章的参数基线算，"
      "凡依赖配套发布清单的量都标明来源。"),
("h3", "8.1　SRAM 读带宽与端口冲突"),
("p", "12 个通道吃的是同一份样本流，一次读操作能服务全部通道，不需要每通道各读一次。"
      "每毫秒要取的新样本固定是 16368 个，所以读次数只取决于 SRAM 字宽。"
      "按 2 bit/样本换算，每字样本数 S = 字宽/2。"),
("table", [["SRAM 字宽", "每字样本数 S", "跟踪读次数/ms", "并发捕获后总读次数/ms", "100 MHz 下占用", "16.368 MHz 下占用"],
 ["32 bit", "16", "1023", "2046", "2.0%", "12.5%"],
 ["16 bit", "8", "2046", "4092", "4.1%", "25.0%"],
 ["8 bit", "4", "4092", "8184", "8.2%", "50.0%"],
 ["2 bit", "1", "16368", "32736", "32.7%", "200%，不可能"]]),
("caption", "表　SRAM 读带宽与端口占用"),
("p", "看最后一列。只要时钟不低于 2 倍采样率、字宽不低于 8 bit，单端口 SRAM 同时喂跟踪和捕获是够的。"
      "时钟接近 16.368 MHz 或者字宽只有 2 bit 时，跟踪自己就把带宽占满了，捕获再插进来必然丢样。"),
("p", "不管时钟多少，都建议给捕获配一份 1 ms 快照缓冲。捕获做多普勒搜索要反复回放同一段数据，"
      "在本地缓冲里回放比反复读 SRAM 省带宽，也容易保证跟踪侧一个样本都不丢。"
      "按 32 bit 字算，16368 个样本 × 2 bit = 4092 字节，也就是 1023 个字。"),
("h3", "8.2　捕获与跟踪的硬件分工"),
("p", "复用这个词有两种意思，分开说清楚。"),
("p", "第一种是 RTL 模块复用：同一份 carrier_mixer_nco、code_nco、correlator_epl 源码例化两次，"
      "一份给 12 个跟踪通道，一份给捕获引擎。代码只有一套，硬件是两套。"),
("p", "第二种是运行期时分复用：捕获和跟踪抢同一份混频与相关硬件。这样会打断跟踪的 1 样本每时钟流水，"
      "仲裁逻辑也不简单，首版不采用。"),
("table", [["方案", "混频乘法器", "累加器端口", "控制复杂度", "首版取舍"],
 ["12 通道全并行，捕获独立例化（同一份 RTL）", "24 + 2", "72 个触发器累加器，无端口竞争", "低", "采用"],
 ["捕获时分复用跟踪数据通路", "24", "捕获插入时会打断跟踪流水", "中", "不采用"],
 ["通道间 2 路时分复用", "12", "36 个累加器需要双端口", "高", "留作面积优化"],
 ["通道间 3 路时分复用", "8", "累加器需要 3 个读端口", "更高", "留作面积优化"]]),
("caption", "表　捕获与跟踪的硬件分工"),
("p", "时分复用省下的是乘法器，代价落在累加器端口上。要读写的累加器每样本有 72 个，"
      "复用倍数越高，需要的端口越多，寄存器堆的面积和功耗上涨，未必划算。"
      "先把功能做对，面积优化等综合报告出来再说。"),
("h3", "8.3　12 通道资源估算"),
("table", [["资源", "每通道", "12 通道合计", "说明"],
 ["相关累加器", "6 × 26 bit = 156 bit", "1872 bit", "E/P/L 各 I/Q，触发器实现"],
 ["20 ms 合并累加器", "2 × 32 bit = 64 bit", "768 bit", "去 NH 后的数据位判决"],
 ["环路状态", "约 120 bit", "约 1440 bit", "环路积分项、系数寄存器、锁定计数"],
 ["载波与码 NCO", "2 × 32 bit = 64 bit", "768 bit", "相位累加器"],
 ["载波 sin/cos ROM", "—", "20480 bit（共享 1 份）", "1024 项 × 10 bit × sin/cos"],
 ["PRN 码 RAM", "2046 bit", "24552 bit", "每通道跟踪不同卫星，不能共用"]]),
("caption", "表　12 通道资源估算"),
("p", "触发器合计约 4900 bit，ROM 与 RAM 合计约 45 kbit。这个量级放在课程工艺上不是瓶颈，"
      "真正的面积大头在相关器与环路里的乘法器，见位宽与周期预算第 8 节。"),
("p", "PRN 码 12 份不能省，因为每个通道盯的是不同卫星。若改成 63 颗星的共享 ROM（63 × 2046 = 128.9 kbit），"
      "省下的是装载动作，但 ROM 面积是原来的 5 倍多，不划算。每通道一份可装载 RAM 更合适，"
      "分配任务时花 2046 个时钟装一次。"),
("h3", "8.4　通道状态编码与超时参数"),
("p", "状态用 4 bit 编码，留足扩展余地。"),
("table", [["状态", "编码", "进入条件", "超时值", "超时动作"],
 ["IDLE", "4'd0", "复位或释放通道", "—", "—"],
 ["ACQUIRE", "4'd1", "收到 allocate 与 init", "取决于搜索配置", "上报 ACQ_TIMEOUT，回 IDLE"],
 ["TRACK_PULL_IN", "4'd2", "捕获初值已装载", "200 ms", "cancel，回 REACQUIRE"],
 ["TRACK_LOCKED", "4'd3", "锁定计数达标", "—", "失锁即转 LOST"],
 ["BIT_SYNC", "4'd4", "开始累加 NH20 相关", "2000 ms", "上报 NAV_SYNC_TIMEOUT，回 LOST"],
 ["FRAME_SYNC", "4'd5", "位流连续", "34000 ms", "上报 NAV_SYNC_TIMEOUT，回 LOST"],
 ["NAV_VALID", "4'd6", "子帧译码且 BCH 通过", "6000 ms", "连续失败则回 LOST"],
 ["LOST", "4'd7", "锁定计数归零或超时", "100 ms", "转 REACQUIRE"],
 ["REACQUIRE", "4'd8", "重捕获计时到", "—", "generation 自增后回 ACQUIRE"]]),
("caption", "表　通道状态编码与超时"),
("p", "超时值是设计起点：200 ms 对应 10 个数据位，2000 ms 对应 100 位，34000 ms 留出一个完整主帧（30 s）再放宽。"
      "ACQUIRE 的超时跟搜索配置走，不是固定值。这些数在拿到配套评估器基线后要重新对齐，"
      "在此之前只作为自洽的默认值。"),
("h3", "8.5　捕获移交跟踪的时序与回退"),
("p", "从捕获成功到跟踪稳定，中间要过五步。"),
("code", "manager          engine              channel\n   |-- allocate/init -->|                    |\n   |-- search_req ----->|                    |\n   |                     |-- 逐假设积分 1 ms    |\n   |<-- search_result ---|                    |\n   |-- 多假设确认(可选) -->|                    |\n   |-- init(初值+生效时刻) ------------------->|\n   |                     |                    |-- PULL_IN 200 ms\n   |<-- channel_status(locked) ----------------|\n   |                     |                    |-- BIT_SYNC\n   |-- 移交完成 --------->|                    |"),
("table", [["步骤", "动作", "判据", "失败时的动作"],
 ["1", "manager 选空闲通道，写 allocate（channel_id、generation、PRN）", "通道处于 IDLE", "无空闲通道则排队等待"],
 ["2", "manager 发 search_req（PRN、task_id、搜索范围、积分配置、窗口参考）", "engine 空闲", "忙则排队，不覆盖在途任务"],
 ["3", "engine 逐假设积分 1 ms 并在过门限时给出 search_result", "峰值超过门限", "全假设失败则换多普勒位或下一颗星，重试计数加一"],
 ["4", "manager 对相邻假设做确认，压虚警", "至少两个相邻假设同时过门限", "确认失败按捕获失败处理"],
 ["5", "manager 发 init，把码相位、多普勒和生效时刻交给通道", "通道接受", "通道忙则取消本次移交"],
 ["6", "通道在 PULL_IN 跑 200 ms", "锁定计数达到 200", "超时则 cancel，generation 自增，回 REACQUIRE"],
 ["7", "通道进入 BIT_SYNC 与 FRAME_SYNC，开始产出观测量", "位边界与子帧头确认", "超时回 LOST，本代次测量作废"]]),
("caption", "表　捕获移交跟踪的步骤与回退"),
("p", "回退路径归成五种情况。"),
("bullets", ["单个假设没过门限：engine 内部推进到下一个假设，通道状态不变。",
 "全部假设失败：manager 换一个多普勒位或下一颗星，重试计数加一。",
 "虚警，也就是跟踪 200 ms 没锁上：cancel 该通道，generation 自增，回 REACQUIRE。",
 "重试次数超过上限：上报 ACQ_FAIL，通道回 IDLE 并释放资源。",
 "跟踪过程中失锁：进 LOST，撤销本代次的有效测量，再走 REACQUIRE。"]),
("p", "这里有个必须提前说清楚的问题：码相位串行扫描太慢。"
      "2046 个码相位乘以 41 个多普勒位（正负 10 kHz、步长 500 Hz）是 83886 个假设，"
      "每个假设 1 ms，一轮冷启动要 84 s。如果验收对捕获时间有要求，"
      "就得把码相位改成并行搜索，例如用匹配滤波器或频域相关，"
      "这样每个多普勒位只需毫秒量级，整轮降到秒级，代价是相关资源要翻十几倍。"),
("p", "首版先做串行扫描，把功能跑通，只在冷启动和重捕获时用。"
      "捕获总耗时按任务书要求作为评价指标，具体门槛等配套基线出来再定。"),
("h2", "9　待确认与风险"),
("table", [["#", "事项", "状态", "影响"],
 ["R1", "配套环境发布清单：SRAM 字宽、读延迟、样本数，目标时钟，工艺库，时序角", "未提供，按指导书 12.1 节报告缺失，不猜数", "阻塞综合与后端"],
 ["R2", "G2 抽头表 PRN 38 到 63，以及移位方向复核", "已转录 37 组，自相关次峰 134 偏大", "影响 PRN 码正确性"],
 ["R3", "跟踪通道 code_phase 观测异常（ISSUE-001）", "已复现并定位方向", "阻塞 L2 回归转绿"],
 ["R4", "捕获引擎 RTL 未实现", "参考模型已验证，码相位 123.000 chip 命中", "本阶段后续任务"],
 ["R5", "环路系数与门限未冻结", "当前是一组自洽默认值", "影响灵敏度与动态指标"],
 ["R6", "码相位串行扫描的冷启动耗时约 84 s（83886 个假设）", "已定量，未定门槛", "若任务书要求捕获时间，需改成码相位并行"],
 ["R7", "SRAM 字宽与读延迟未知，快照缓冲的大小和读时序按 32 bit 字预估", "等配套清单", "影响取数层接口与带宽核算"]]),
("caption", "表 17　待确认与风险"),
]

TITLE = "北斗B1I基带处理器_总体架构方案"
FIG_W_CM = 15.0   # A4 去掉左右各 28 mm 页边距后可用 15.4 cm，留一点余量


import re as _re
_TBL = [0]
_FIG = [0]


def _renum(text):
    m = _re.match(r"^(表|图)\s*(\d+)?\s*(.*)$", text)
    if not m:
        return text
    if m.group(1) == "表":
        _TBL[0] += 1
        return "表 %d　%s" % (_TBL[0], m.group(3))
    _FIG[0] += 1
    return "图 %d　%s" % (_FIG[0], m.group(3))


def _reset():
    _TBL[0] = 0
    _FIG[0] = 0


def build_md():
    _reset()
    L = []
    for kind, payload in DOC:
        if kind == "h1":
            L += ["# " + payload, ""]
        elif kind == "h2":
            L += ["## " + payload, ""]
        elif kind == "h3":
            L += ["### " + payload, ""]
        elif kind == "p":
            L += ["　　" + payload, ""]
        elif kind == "caption":
            L += ["**" + _renum(payload) + "**", ""]
        elif kind == "figure":
            L += ["![架构图](03_架构图.png)", "", "**" + _renum(payload) + "**", ""]
        elif kind == "code":
            L += [BT * 3 + "text", payload, BT * 3, ""]
        elif kind == "table":
            head, rows = payload[0], payload[1:]
            L += ["| " + " | ".join(head) + " |",
                  "|" + "|".join(["---"] * len(head)) + "|"]
            for r in rows:
                L += ["| " + " | ".join(str(c) for c in r) + " |"]
            L += [""]
    return "\n".join(L) + "\n"


def add_caption(doc, text, size_pt=10.5):
    from docx.shared import Pt
    from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.SINGLE
    p.paragraph_format.line_spacing = None
    r = p.add_run(text)
    r.bold = True
    r.font.size = Pt(size_pt)
    r.font.name = "宋体"
    r._element.rPr.rFonts.set(__import__("docx").oxml.ns.qn("w:eastAsia"), "宋体")
    return p


def build_docx(path):
    _reset()
    from docx import Document
    from docx.shared import Pt, Cm
    from docx.oxml.ns import qn
    from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING

    doc = Document()
    from docx.shared import Mm
    for sec in doc.sections:
        sec.page_width = Mm(210)
        sec.page_height = Mm(297)
        sec.top_margin = Mm(25)
        sec.bottom_margin = Mm(25)
        sec.left_margin = Mm(28)
        sec.right_margin = Mm(28)
    # 正文：宋体 小四(12pt)，行距固定 22 磅，首行缩进 2 字符
    normal = doc.styles["Normal"]
    normal.font.name = "宋体"
    normal.font.size = Pt(12)
    normal.element.rPr.rFonts.set(qn("w:eastAsia"), "宋体")
    pf = normal.paragraph_format
    pf.line_spacing_rule = WD_LINE_SPACING.EXACTLY
    pf.line_spacing = Pt(22)
    pf.first_line_indent = Pt(24)
    pf.space_before = Pt(0)
    pf.space_after = Pt(0)

    for kind, payload in DOC:
        if kind == "h1":
            p = doc.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.first_line_indent = Pt(0)
            r = p.add_run(payload)
            r.bold = True
            r.font.size = Pt(22)
            r.font.name = "宋体"
            r._element.rPr.rFonts.set(qn("w:eastAsia"), "宋体")
        elif kind in ("h2", "h3"):
            p = doc.add_paragraph()
            p.paragraph_format.first_line_indent = Pt(0)
            p.paragraph_format.space_before = Pt(6)
            r = p.add_run(payload)
            r.bold = True
            r.font.size = Pt(14)          # 子标题：四号
            r.font.name = "宋体"
            r._element.rPr.rFonts.set(qn("w:eastAsia"), "宋体")
        elif kind == "p":
            doc.add_paragraph(payload)
        elif kind == "caption":
            add_caption(doc, _renum(payload))
        elif kind == "figure":
            p = doc.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.first_line_indent = Pt(0)
            # 关键：正文是"固定值 22 磅"，图片必须改成单倍行距，否则会被裁成一条
            p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.SINGLE
            p.paragraph_format.line_spacing = None
            p.paragraph_format.space_before = Pt(6)
            p.paragraph_format.space_after = Pt(3)
            p.add_run().add_picture(FIG, width=Cm(FIG_W_CM))
            add_caption(doc, _renum(payload))
        elif kind == "code":
            p = doc.add_paragraph()
            p.paragraph_format.first_line_indent = Pt(0)
            r = p.add_run(payload)
            r.font.name = "Consolas"
            r.font.size = Pt(9)
        elif kind == "table":
            head, rows = payload[0], payload[1:]
            t = doc.add_table(rows=1, cols=len(head))
            t.style = "Table Grid"
            for i, h in enumerate(head):
                cell = t.rows[0].cells[i]
                cell.text = ""
                run = cell.paragraphs[0].add_run(str(h))
                run.bold = True
                run.font.size = Pt(10.5)   # 表头：五号加粗
                run.font.name = "宋体"
                run._element.rPr.rFonts.set(qn("w:eastAsia"), "宋体")
            for row in rows:
                cells = t.add_row().cells
                for i, c in enumerate(row):
                    cells[i].text = ""
                    run = cells[i].paragraphs[0].add_run(str(c))
                    run.font.size = Pt(10.5)
                    run.font.name = "宋体"
                    run._element.rPr.rFonts.set(qn("w:eastAsia"), "宋体")
    doc.save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    md = os.path.join(OUT, TITLE + ".md")
    dx = os.path.join(OUT, TITLE + ".docx")
    with open(md, "w", encoding="utf-8", newline="\n") as f:
        f.write(build_md())
    build_docx(dx)
    print("已生成:", md)
    print("已生成:", dx)
    return 0


if __name__ == "__main__":
    sys.exit(main())
