// =============================================================================
// tracking_channel.sv -- 单通道跟踪数据通路（可复制为 12 通道，参数化展开）
//   载波 NCO/混频 -> 码 NCO -> 码 RAM 三抽头 -> E/P/L 相干累加 -> DLL/PLL
//   全部状态在触发器内，通道之间无共享状态（除只读码 RAM 与常系数）
//   需求: REQ-TRK-001/002/003/005
// =============================================================================
`include "b1i_params.svh"

module tracking_channel (
  input  logic                            clk,
  input  logic                            rst_n,
  input  logic                            sample_valid,
  input  logic                            ms_tick,
  input  logic signed [SAMPLE_W-1:0]      sample,
  // 码 RAM 加载（PRN 码表由外部按 ICD 装填）
  input  logic                            code_we,
  input  logic [10:0]                     code_waddr,
  input  logic                            code_wdata,
  // 初始化（来自捕获结果）
  input  logic                            init_load,
  input  logic [NCO_PHASE_W-1:0]          init_carrier_phase,
  input  logic [CODE_PHASE_W-1:0]         init_code_phase,
  input  logic signed [FREQ_WORD_W-1:0]   init_doppler,
  input  logic [3:0]                      code_spacing,
  input  logic                            fll_en,
  input  logic signed [CORR_ACC_W-1:0]    lock_thresh,
  // 观测输出
  output logic                            dump_valid,
  output logic signed [CORR_ACC_W-1:0]    i_e,
  output logic signed [CORR_ACC_W-1:0]    q_e,
  output logic signed [CORR_ACC_W-1:0]    i_p,
  output logic signed [CORR_ACC_W-1:0]    q_p,
  output logic signed [CORR_ACC_W-1:0]    i_l,
  output logic signed [CORR_ACC_W-1:0]    q_l,
  output logic [CODE_PHASE_W-1:0]         code_phase,
  output logic [10:0]                     chip_idx,
  output logic [FREQ_WORD_W-1:0]          freq_word,
  output logic                            locked,
  output logic signed [15:0]              dll_dbg,
  output logic signed [15:0]              pll_dbg
);

  logic signed [SAMPLE_W+CARR_LUT_DATA_W-1:0] mix_i, mix_q;
  logic                                       e_tap, p_tap, l_tap;
  logic [10:0]                                e_idx, l_idx;
  logic [NCO_PHASE_W-1:0]                     carr_phase;
  logic signed [CODE_PHASE_W-1:0]             code_inc;
  logic signed [CORR_ACC_W-1:0]               a_i_e, a_q_e, a_i_p, a_q_p, a_i_l, a_q_l;

  carrier_mixer_nco u_carrier (
    .clk         (clk),
    .rst_n       (rst_n),
    .sample_valid(sample_valid),
    .sample      (sample),
    .freq_word   (freq_word),
    .load        (init_load),
    .phase_init  (init_carrier_phase),
    .phase       (carr_phase),
    .mix_i       (mix_i),
    .mix_q       (mix_q)
  );

  code_nco u_code_nco (
    .clk             (clk),
    .rst_n           (rst_n),
    .sample_valid    (sample_valid),
    .code_inc        (code_inc),
    .load            (init_load),
    .phase_init      (init_code_phase),
    .code_phase      (code_phase),
    .chip_idx        (chip_idx),
    .code_epoch_tick ()
  );

  code_ram u_code_ram (
    .clk     (clk),
    .rst_n   (rst_n),
    .we      (code_we),
    .waddr   (code_waddr),
    .wdata   (code_wdata),
    .chip_idx(chip_idx),
    .spacing (code_spacing),
    .e_tap   (e_tap),
    .p_tap   (p_tap),
    .l_tap   (l_tap),
    .e_idx   (e_idx),
    .l_idx   (l_idx)
  );

  correlator_epl u_corr (
    .clk        (clk),
    .rst_n      (rst_n),
    .sample_valid(sample_valid),
    .ms_tick    (ms_tick),
    .mix_i      (mix_i),
    .mix_q      (mix_q),
    .e_tap      (e_tap),
    .p_tap      (p_tap),
    .l_tap      (l_tap),
    .acc_i_e    (a_i_e), .acc_q_e (a_q_e),
    .acc_i_p    (a_i_p), .acc_q_p (a_q_p),
    .acc_i_l    (a_i_l), .acc_q_l (a_q_l),
    .dump_valid (dump_valid),
    .dump_i_e   (i_e), .dump_q_e (q_e),
    .dump_i_p   (i_p), .dump_q_p (q_p),
    .dump_i_l   (i_l), .dump_q_l (q_l)
  );

  dll_loop u_dll (
    .clk     (clk),
    .rst_n   (rst_n),
    .update  (dump_valid),
    .i_e     (i_e), .q_e (q_e),
    .i_l     (i_l), .q_l (q_l),
    .code_inc(code_inc),
    .disc_dbg(dll_dbg),
    .integ_dbg()
  );

  fll_pll_loop u_pll (
    .clk        (clk),
    .rst_n      (rst_n),
    .update     (dump_valid),
    .fll_en     (fll_en),
    .load       (init_load),
    .init_doppler(init_doppler),
    .i_p        (i_p), .q_p (q_p),
    .lock_thresh(lock_thresh),
    .freq_word  (freq_word),
    .disc_dbg   (pll_dbg),
    .locked     (locked),
    .lock_cnt   ()
  );

endmodule
