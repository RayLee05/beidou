// =============================================================================
// b1i_params.svh -- 北斗 B1I 基带处理器全局参数（RTL 侧唯一定义处）
//
// 本文件与 sw/b1i_ref/params.py 逐项一致，由 scripts/check_params_consistency.py
// 自动比对，禁止单侧修改。
//
// 用法：\`include "b1i_params.svh"   (编译时 -I rtl/include)
// =============================================================================

`ifndef B1I_PARAMS_SVH
`define B1I_PARAMS_SVH

// ---- 版本 ----
localparam int unsigned B1I_PARAMS_VERSION_MAJOR = 0;
localparam int unsigned B1I_PARAMS_VERSION_MINOR = 2;

// ---- 射频与中频 ----
localparam longint unsigned F_RF_HZ  = 1561098000;   // 1561.098 MHz
// 依据实验指导书 1.2/2.3 节：每码片 8 样本，Fs = 8*2.046M = 16.368 MHz，fIF = Fs/4
localparam int    unsigned F_IF_HZ   = 4092000;
localparam int    unsigned F_S_HZ    = 16368000;

// ---- 量化与打包 ----
localparam int unsigned SAMPLE_BITS      = 2;
localparam int unsigned SAMPLES_PER_BYTE = 4;
localparam int unsigned SAMPLE_W         = 3;        // signed，-3..+3

// ---- 测距码 / 二级码 / 电文 ----
localparam int unsigned CODE_RATE_HZ           = 2046000;
localparam int unsigned CODE_CHIPS_PER_PERIOD  = 2046;
localparam int unsigned NH_LENGTH              = 20;
localparam int unsigned D1_BIT_RATE_BPS        = 50;
localparam int unsigned D1_BIT_PERIOD_MS       = 20;
localparam int unsigned D1_SUBFRAME_PERIOD_S   = 6;
localparam int unsigned D1_SUBFRAMES_PER_FRAME = 5;
localparam int unsigned D1_FRAME_PERIOD_S      = 30;

// ---- 接收机结构 ----
localparam int unsigned N_CHANNELS      = 12;
localparam int unsigned CHANNEL_ID_W    = 4;
localparam int unsigned PRN_W           = 6;

// ---- 定点位宽 ----
localparam int unsigned NCO_PHASE_W     = 32;
localparam int unsigned CARR_LUT_ADDR_W = 10;
localparam int unsigned CARR_LUT_DATA_W = 10;
localparam int unsigned CORR_ACC_W      = 26;
localparam int unsigned BIT_ACC_W       = 32;
localparam int unsigned LOOP_COEF_W     = 16;
localparam int unsigned LOOP_COEF_FRAC_W= 14;
localparam int unsigned FREQ_WORD_W     = 32;
localparam int unsigned CODE_PHASE_W    = 32;
localparam int unsigned SAMPLE_INDEX_W  = 32;
localparam int unsigned EPOCH_ID_W      = 32;

// ---- 码相位定点（Q(11.21)，见 docs/FIXED_POINT.md 第 6 节）----
// 码相位 = 整数码片[31:21] + 小数码片[20:0]；一个码周期 = 2046 << 21
localparam int unsigned CODE_FRAC_W      = 21;
localparam logic [31:0] CODE_PERIOD_WORD = 32'd4290772992;  // = 2046 << 21
localparam int unsigned CODE_INC_NOMINAL = 262144;          // = 2046/16368 * 2^21 = 2^21/8，精确

// ---- 码 NCO 内部累加器（Q(11.37)，48 bit；对外 code_phase 取高 32 位）----
localparam int unsigned CODE_NCO_W           = 48;
localparam int unsigned CODE_NCO_FRAC_W      = 37;
localparam logic [47:0] CODE_NCO_PERIOD      = 48'd281200098803712;  // = 2046 << 37
localparam logic [47:0] CODE_NCO_INC_NOMINAL = 48'd17179869184;      // = 2^34（每码片 8 样本）
localparam int unsigned CODE_SPACING_DEFAULT = 4;                    // E/L 偏移，单位 1/8 chip

// ---- 载波频率字 ----
localparam logic [31:0] FREQ_WORD_IF      = 32'd1073741824; // = 2^30 = Fs/4，精确表示 4.092 MHz
localparam logic [31:0] FREQ_WORD_DOP_MAX = 32'd2883584;    // ≈ ±10.99 kHz（±10 kHz + 动态余量）

// ---- 环路（推导见 docs/TRACKING_DESIGN.md 第 4 节；系数可由配置寄存器覆盖）----
localparam int unsigned NORM_W         = 12;       // 归一化后满幅 ≈ 2^12
localparam int unsigned AMP_SHIFT      = 3;
localparam int unsigned AMP_MIN        = 64;
localparam int unsigned PLL_KP_DEFAULT = 6685;     // Q2.14
localparam int unsigned PLL_KI_DEFAULT = 134;      // Q2.14
localparam int unsigned FLL_K_DEFAULT  = 6685;     // Q2.14
localparam int unsigned DLL_KP_DEFAULT = 2099;     // Q8.8
localparam int unsigned DLL_KI_DEFAULT = 4;        // Q8.8
localparam int unsigned DLL_ACC_MAX    = 131072;
localparam int unsigned CODE_AID_COEF  = 2749;     // code_aid = (dop_word * 2749) >>> 16
localparam int unsigned CODE_AID_SHIFT = 16;
localparam int unsigned LOCK_BLOCK     = 20;
localparam int unsigned LOCK_ON        = 5;
localparam int unsigned LOCK_MAX       = 10;

// ---- 派生常量 ----
localparam int unsigned SAMPLES_PER_MS      = F_S_HZ / 1000;             // 16368
localparam int unsigned SAMPLES_PER_BIT     = F_S_HZ / D1_BIT_RATE_BPS;  // 327680
localparam int unsigned SAMPLES_PER_SUBFRAME= F_S_HZ * D1_SUBFRAME_PERIOD_S;
localparam int unsigned SAMPLES_PER_FRAME   = F_S_HZ * D1_FRAME_PERIOD_S;
localparam int unsigned MS_PER_BIT          = 1000 / D1_BIT_RATE_BPS;    // 20
localparam int unsigned MS_PER_SUBFRAME     = D1_SUBFRAME_PERIOD_S * 1000;// 6000
localparam int unsigned MS_PER_FRAME        = D1_FRAME_PERIOD_S * 1000;   // 30000

// ---- 时基回绕 ----
// SAMPLE_INDEX 回绕周期 = 2**SAMPLE_INDEX_W / F_S_HZ，由
// scripts/fixed_point_budget.py 推导并写入 reports/fixed_point_budget.md，
// 不在 RTL 中硬编码。

`endif // B1I_PARAMS_SVH
