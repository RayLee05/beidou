// =============================================================================
// tracking_channel.sv -- 单通道跟踪（12 通道用 generate 复制，通道间无共享状态）
//   载波 NCO/混频 -> 码 NCO -> 码 RAM 三抽头 -> E/P/L 相干累加 -> track_loop
//
//   窗口：按本通道码周期划分，码 NCO 越界的样本是窗口最后一个样本。
//   参数：窗口内 freq_word / code_inc 不变；越界样本处装入 track_loop 已算好的
//         pend 值（窗口 j 的观测量 -> 用于窗口 j+2）。
//   装载：init_load 一拍装入码相位/载波相位/多普勒，清零累加器与 ms_count；
//         装载后的第一个窗口不完整，dump 照常输出（dump_partial=1）但不更新环路。
//   计数：ms_count 在每个越界样本加 1；dump_ms 是该窗口的标签（= 加 1 前的值）。
//   逐位参考：sw/b1i_ref/tracking_model.py
//   需求: REQ-TRK-001/002/003/005
// =============================================================================
`include "b1i_params.svh"

module tracking_channel (
  input  logic                            clk,
  input  logic                            rst_n,
  input  logic                            enable,
  input  logic                            sample_valid,
  input  logic signed [SAMPLE_W-1:0]      sample,
  // 码 RAM 装载（PRN 码由 prn_code_gen 生成）
  input  logic                            code_we,
  input  logic [10:0]                     code_waddr,
  input  logic                            code_wdata,
  // 初始化（来自捕获移交）
  input  logic                            init_load,
  input  logic [NCO_PHASE_W-1:0]          init_carrier_phase,
  input  logic [CODE_NCO_W-1:0]           init_code_phase,
  input  logic signed [FREQ_WORD_W-1:0]   init_doppler,
  // 配置
  input  logic [3:0]                      code_spacing,   // 1/8 chip 单位
  input  logic                            fll_en,
  input  logic signed [15:0]              pll_kp,
  input  logic signed [15:0]              pll_ki,
  input  logic signed [15:0]              fll_k,
  input  logic signed [15:0]              dll_kp,
  input  logic signed [15:0]              dll_ki,
  // 观测输出
  output logic                            dump_valid,
  output logic                            dump_partial,
  output logic [31:0]                     dump_ms,
  output logic signed [CORR_ACC_W-1:0]    i_e, q_e, i_p, q_p, i_l, q_l,
  output logic [CODE_PHASE_W-1:0]         code_phase,     // Q(11.21)，已处理样本
  output logic [31:0]                     ms_count,
  output logic                            epoch_tick,     // 越界样本同拍（已门控）
  output logic [FREQ_WORD_W-1:0]          freq_word,
  output logic signed [FREQ_WORD_W-1:0]   dop_word,
  output logic                            locked,
  output logic [3:0]                      lock_cnt,
  output logic signed [15:0]              d_pll_dbg,
  output logic signed [15:0]              d_fll_dbg,
  output logic signed [15:0]              d_dll_dbg
);

  logic                                       sv;
  logic signed [SAMPLE_W+CARR_LUT_DATA_W-1:0] mix_i, mix_q;
  logic [NCO_PHASE_W-1:0]                     carr_phase;
  logic [CODE_NCO_W-1:0]                      cp_q, cp_next, code_inc;
  logic                                       epoch_c;
  logic [CODE_NCO_W-1:0]                      pend_code_inc;
  logic [FREQ_WORD_W-1:0]                     pend_freq_word;
  logic                                       e_tap, p_tap, l_tap;
  logic [10:0]                                e_idx, p_idx, l_idx;
  logic                                       partial_q;
  logic [31:0]                                ms_q;
  logic                                       loop_busy;

  assign sv         = enable & sample_valid & ~init_load;
  assign epoch_tick = sv & epoch_c;

  // 初始多普勒限幅（与 track_loop 的频率积分器范围一致）
  logic signed [FREQ_WORD_W-1:0] init_dop_c;
  always_comb begin
    if (init_doppler > $signed(FREQ_WORD_DOP_MAX))       init_dop_c = $signed(FREQ_WORD_DOP_MAX);
    else if (init_doppler < -$signed(FREQ_WORD_DOP_MAX)) init_dop_c = -$signed(FREQ_WORD_DOP_MAX);
    else                                                 init_dop_c = init_doppler;
  end

  // ---------------------------------------------------------------- NCO
  carrier_mixer_nco u_carrier (
    .clk(clk), .rst_n(rst_n), .sample_valid(sv), .sample(sample),
    .freq_word(freq_word), .load(init_load), .phase_init(init_carrier_phase),
    .phase(carr_phase), .mix_i(mix_i), .mix_q(mix_q));

  code_nco u_code_nco (
    .clk(clk), .rst_n(rst_n), .sample_valid(sv), .code_inc(code_inc),
    .load(init_load), .phase_init(init_code_phase),
    .phase(cp_q), .phase_next(cp_next), .code_epoch(epoch_c));

  // E/P/L 抽头相位：E = P + d，L = P - d（模码周期）
  logic [CODE_NCO_W:0]   e_sum;
  logic [CODE_NCO_W-1:0] e_ph, l_ph, dsp;
  always_comb begin
    dsp   = CODE_NCO_W'(code_spacing) << (CODE_NCO_FRAC_W - 3);
    e_sum = {1'b0, cp_next} + {1'b0, dsp};
    e_ph  = (e_sum >= {1'b0, CODE_NCO_PERIOD}) ? e_sum[CODE_NCO_W-1:0] - CODE_NCO_PERIOD
                                               : e_sum[CODE_NCO_W-1:0];
    l_ph  = (cp_next >= dsp) ? cp_next - dsp : cp_next + CODE_NCO_PERIOD - dsp;
    p_idx = cp_next[CODE_NCO_W-1 -: 11];
    e_idx = e_ph[CODE_NCO_W-1 -: 11];
    l_idx = l_ph[CODE_NCO_W-1 -: 11];
  end

  code_ram u_code_ram (
    .clk(clk), .we(code_we), .waddr(code_waddr), .wdata(code_wdata),
    .e_idx(e_idx), .p_idx(p_idx), .l_idx(l_idx),
    .e_tap(e_tap), .p_tap(p_tap), .l_tap(l_tap));

  correlator_epl u_corr (
    .clk(clk), .rst_n(rst_n), .clear(init_load), .sample_valid(sv), .win_last(epoch_c),
    .mix_i(mix_i), .mix_q(mix_q), .e_tap(e_tap), .p_tap(p_tap), .l_tap(l_tap),
    .dump_valid(dump_valid),
    .dump_i_e(i_e), .dump_q_e(q_e), .dump_i_p(i_p),
    .dump_q_p(q_p), .dump_i_l(i_l), .dump_q_l(q_l));

  // ---------------------------------------------------------------- 窗口参数与计数
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      freq_word    <= FREQ_WORD_IF;
      code_inc     <= CODE_NCO_INC_NOMINAL;
      partial_q    <= 1'b1;
      dump_partial <= 1'b1;
      ms_q         <= '0;
      dump_ms      <= '0;
    end else if (init_load) begin
      // 与 track_loop 装载后的 pend 值一致：IF + 多普勒，码率含载波辅助
      freq_word    <= FREQ_WORD_IF + init_dop_c;
      code_inc     <= CODE_NCO_INC_NOMINAL
                      + CODE_NCO_W'((45'(init_dop_c) * 45'sd2749) >>> CODE_AID_SHIFT);
      partial_q    <= 1'b1;
      ms_q         <= '0;
    end else if (sv && epoch_c) begin
      freq_word    <= pend_freq_word;
      code_inc     <= pend_code_inc;
      dump_partial <= partial_q;
      dump_ms      <= ms_q;
      partial_q    <= 1'b0;
      ms_q         <= ms_q + 32'd1;
    end
  end

  assign ms_count   = ms_q;
  assign code_phase = cp_q[CODE_NCO_W-1 -: CODE_PHASE_W];

  // ---------------------------------------------------------------- 环路
  track_loop u_loop (
    .clk(clk), .rst_n(rst_n), .load(init_load), .init_dop(init_dop_c),
    .fll_en(fll_en), .pll_kp(pll_kp), .pll_ki(pll_ki), .fll_k(fll_k),
    .dll_kp(dll_kp), .dll_ki(dll_ki),
    .start(dump_valid & ~dump_partial),
    .i_e(i_e), .q_e(q_e), .i_p(i_p), .q_p(q_p), .i_l(i_l), .q_l(q_l),
    .pend_freq_word(pend_freq_word), .pend_code_inc(pend_code_inc),
    .dop_word(dop_word), .busy(loop_busy), .locked(locked), .lock_cnt(lock_cnt),
    .amp_dbg(), .d_pll_dbg(d_pll_dbg), .d_fll_dbg(d_fll_dbg), .d_dll_dbg(d_dll_dbg));

endmodule
