// =============================================================================
// b1i_records.svh -- 结构化输出记录（256 bit）字段定义
//   RTL（b1i_rx_top）与软件解析（sw/rinex/records.py）共用此定义，改动须同步两侧。
//   通用：[255:252] 记录类型
//
//   EPOCH  (1)  每个公共历元一条，紧随其后是 N_CHANNELS 条 MEAS
//     [251:220] epoch_id  [219:188] sample_count（历元时刻已处理样本数）
//     [187:176] 有效测量通道数  [175] input_done
//     [174:143] sow0_ms（样本 0 的接收机本地周内毫秒；0=未配置）
//   MEAS   (2)  每通道一条（无效通道也输出，meas_valid=0）
//     [251:248] channel  [247:242] prn  [241:234] generation  [233:202] epoch_id
//     [201:170] tx_ms（发射时刻周内毫秒，整数部分）
//     [169:138] code_phase（Q11.21 chip，码周期内）
//     [137:106] dop_word（有符号，Hz = dop_word * Fs / 2^32）
//     [105:74]  ms_count（通道码周期计数）
//     [73] meas_valid  [72] locked  [71] bit_synced  [70] time_valid
//     [69:67] ch_state  [66:63] lock_cnt  [62:50] week  [49] week_valid
//   NAV    (3)  每个译码成功的子帧一条
//     [251:248] channel  [247:242] prn  [241:238] generation[3:0]  [237:235] sf_id
//     [234:230] BCH 纠错次数  [229] 极性反相  [223:0] 224 位信息位（[223] 为首位）
//   STATUS (4)  事件
//     [251:248] channel  [247:242] prn  [241:234] generation  [233:202] sample_count
//     [201:198] 事件码  [197:166] 附加 1  [165:134] 附加 2  [133:122] 附加 3
// =============================================================================
`ifndef B1I_RECORDS_SVH
`define B1I_RECORDS_SVH

localparam logic [3:0] REC_EPOCH  = 4'd1;
localparam logic [3:0] REC_MEAS   = 4'd2;
localparam logic [3:0] REC_NAV    = 4'd3;
localparam logic [3:0] REC_STATUS = 4'd4;

// STATUS 事件码
localparam logic [3:0] EV_ACQ_FOUND = 4'd1;   // 附加: peak / dop_word / h
localparam logic [3:0] EV_ACQ_MISS  = 4'd2;   // 附加: peak / mean
localparam logic [3:0] EV_LOCKED    = 4'd3;
localparam logic [3:0] EV_LOST      = 4'd4;
localparam logic [3:0] EV_RELEASED  = 4'd5;   // 附加 1: 原因 1=牵引超时 2=失锁超时
localparam logic [3:0] EV_RELOCKED  = 4'd6;
localparam logic [3:0] EV_BIT_SYNC  = 4'd7;
localparam logic [3:0] EV_FRAME     = 4'd8;
localparam logic [3:0] EV_INPUT_END = 4'd9;
localparam logic [3:0] EV_OVERFLOW  = 4'd10;
localparam logic [3:0] EV_NAV_PARITY = 4'd11;  // BCH/字段校验失败
localparam logic [3:0] EV_NAV_TIMEOUT = 4'd12; // 附加1: 1=位同步 2=帧同步
localparam logic [31:0] ERR_FIFO_OVERFLOW = 32'd10; // 顶层 error_code，与 EV_OVERFLOW 同号

// 通道状态
localparam logic [2:0] CH_IDLE   = 3'd0;
localparam logic [2:0] CH_PULLIN = 3'd1;
localparam logic [2:0] CH_TRACK  = 3'd2;
localparam logic [2:0] CH_LOST   = 3'd3;

function automatic logic [255:0] pack_epoch(
    input logic [31:0] epoch_id,
    input logic [31:0] sample_count,
    input logic [11:0] n_valid,
    input logic        input_done,
    input logic [31:0] sow0_ms
);
  pack_epoch = {REC_EPOCH, epoch_id, sample_count, n_valid, input_done, sow0_ms, 143'b0};
endfunction

function automatic logic [255:0] pack_meas(
    input logic [3:0]  channel,
    input logic [5:0]  prn,
    input logic [7:0]  generation,
    input logic [31:0] epoch_id,
    input logic [31:0] tx_ms,
    input logic [31:0] code_phase,
    input logic [31:0] dop_word,
    input logic [31:0] ms_count,
    input logic        meas_valid,
    input logic        locked,
    input logic        bit_synced,
    input logic        time_valid,
    input logic [2:0]  ch_state,
    input logic [3:0]  lock_cnt,
    input logic [12:0] week,
    input logic        week_valid
);
  pack_meas = {REC_MEAS, channel, prn, generation, epoch_id, tx_ms, code_phase,
               dop_word, ms_count, meas_valid, locked, bit_synced, time_valid,
               ch_state, lock_cnt, week, week_valid, 49'b0};
endfunction

function automatic logic [255:0] pack_nav(
    input logic [3:0]   channel,
    input logic [5:0]   prn,
    input logic [3:0]   generation,
    input logic [2:0]   sf_id,
    input logic [4:0]   fixes,
    input logic         inverted,
    input logic [223:0] info
);
  pack_nav = {REC_NAV, channel, prn, generation, sf_id, fixes, inverted, 5'b0, info};
endfunction

function automatic logic [255:0] pack_status(
    input logic [3:0]  channel,
    input logic [5:0]  prn,
    input logic [7:0]  generation,
    input logic [31:0] sample_count,
    input logic [3:0]  ev,
    input logic [31:0] a1,
    input logic [31:0] a2,
    input logic [11:0] a3
);
  pack_status = {REC_STATUS, channel, prn, generation, sample_count, ev, a1, a2, a3, 122'b0};
endfunction

`endif
