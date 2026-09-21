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
localparam int unsigned B1I_PARAMS_VERSION_MINOR = 1;

// ---- 射频与中频 ----
localparam longint unsigned F_RF_HZ  = 1561098000;   // 1561.098 MHz
localparam int    unsigned F_IF_HZ   = 4096000;      // 课程规格；PDF 4.092 MHz 待确认
localparam int    unsigned F_S_HZ    = 16384000;     // 课程规格；PDF 16.368 MSps 待确认

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

// ---- 派生常量 ----
localparam int unsigned SAMPLES_PER_MS      = F_S_HZ / 1000;             // 16384
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
