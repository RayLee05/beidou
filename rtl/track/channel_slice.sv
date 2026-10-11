// =============================================================================
// channel_slice.sv -- 单通道：跟踪 + NH 位同步 + D1 帧同步
//   12 通道用 generate 复制；码 RAM 写口与 init/clear 由通道管理器驱动。
// =============================================================================
`include "b1i_params.svh"

module channel_slice #(parameter bit WITH_METADATA = 1'b0) (
  input  logic                            clk,
  input  logic                            rst_n,
  input  logic                            enable,
  input  logic                            sample_valid,
  input  logic [63:0]                     sample_count,
  input  logic signed [SAMPLE_W-1:0]      sample,
  input  logic                            code_we,
  input  logic [10:0]                     code_waddr,
  input  logic                            code_wdata,
  input  logic                            init_load,
  input  logic                            clear,
  input  logic [NCO_PHASE_W-1:0]          init_carrier_phase,
  input  logic [CODE_NCO_W-1:0]           init_code_phase,
  input  logic signed [FREQ_WORD_W-1:0]   init_doppler,
  input  logic [3:0]                      code_spacing,
  input  logic                            fll_en,
  input  logic signed [15:0]              pll_kp,
  input  logic signed [15:0]              pll_ki,
  input  logic signed [15:0]              fll_k,
  input  logic signed [15:0]              dll_kp,
  input  logic signed [15:0]              dll_ki,
  output logic                            dump_valid,
  output logic                            dump_partial,
  output logic [31:0]                     dump_ms,
  output logic signed [CORR_ACC_W-1:0]    i_e, q_e, i_p, q_p, i_l, q_l,
  output logic [CODE_PHASE_W-1:0]         code_phase,
  output logic [CODE_NCO_W-1:0]           code_phase_full,
  output logic [CODE_NCO_W-1:0]           code_phase_after_sample,
  output logic [NCO_PHASE_W-1:0]          carrier_phase,
  output logic [31:0]                     ms_count,
  output logic                            epoch_tick,
  output logic [FREQ_WORD_W-1:0]          freq_word,
  output logic signed [FREQ_WORD_W-1:0]   dop_word,
  output logic                            locked,
  output logic [3:0]                      lock_cnt,
  output logic                            bit_synced,
  output logic                            bit_valid,
  output logic                            bit_val,
  output logic [31:0]                     bit_ms,
  output logic                            sf_valid,
  output logic [2:0]                      sf_id,
  output logic [19:0]                     sf_sow,
  output logic [31:0]                     sf_start_ms,
  output logic [223:0]                    sf_info,
  output logic [4:0]                      sf_fixes,
  output logic [299:0]                    sf_raw,
  output logic [9:0][1:0]                 sf_word_fixes,
  output logic [9:0][63:0]                sf_word_samples,
  output logic [9:0][47:0]                sf_word_phases,
  output logic [9:0][31:0]                sf_word_ms,
  output logic                            sf_inverted,
  output logic                            frame_synced,
  output logic                            anchor_valid,
  output logic [31:0]                     anchor_ms,
  output logic [19:0]                     anchor_sow,
  output logic [12:0]                     week,
  output logic                            week_valid,
  output logic                            sf_err
);

  tracking_channel u_trk (
    .clk(clk), .rst_n(rst_n), .enable(enable), .sample_valid(sample_valid),
    .sample(sample), .code_we(code_we), .code_waddr(code_waddr), .code_wdata(code_wdata),
    .init_load(init_load), .init_carrier_phase(init_carrier_phase),
    .init_code_phase(init_code_phase), .init_doppler(init_doppler),
    .code_spacing(code_spacing), .fll_en(fll_en),
    .pll_kp(pll_kp), .pll_ki(pll_ki), .fll_k(fll_k), .dll_kp(dll_kp), .dll_ki(dll_ki),
    .dump_valid(dump_valid), .dump_partial(dump_partial), .dump_ms(dump_ms),
    .i_e(i_e), .q_e(q_e), .i_p(i_p), .q_p(q_p), .i_l(i_l), .q_l(q_l),
    .code_phase(code_phase), .code_phase_full(code_phase_full),
    .code_phase_after_sample(code_phase_after_sample), .carrier_phase(carrier_phase),
    .ms_count(ms_count), .epoch_tick(epoch_tick),
    .freq_word(freq_word), .dop_word(dop_word), .locked(locked), .lock_cnt(lock_cnt),
    .d_pll_dbg(), .d_fll_dbg(), .d_dll_dbg());

  logic [63:0] bit_end_sample;
  logic [47:0] bit_end_phase;
  nh_bit_sync u_nh (
    .clk(clk), .rst_n(rst_n), .clear(clear | init_load),
    .dump_valid(dump_valid), .dump_partial(dump_partial),
    .dump_ms(dump_ms), .i_p(i_p),
    .dump_sample_count(sample_count), .dump_code_phase(code_phase_full),
    .synced(bit_synced), .bit_phase(), .bit_valid(bit_valid),
    .bit_val(bit_val), .bit_ms(bit_ms), .bit_mag(),
    .bit_end_sample(bit_end_sample), .bit_end_phase(bit_end_phase));

  d1_frame_sync #(.WITH_METADATA(WITH_METADATA)) u_d1 (
    .clk(clk), .rst_n(rst_n), .clear(clear | init_load),
    .bit_valid(bit_valid), .bit_val(bit_val), .bit_ms(bit_ms),
    .bit_end_sample(bit_end_sample), .bit_end_phase(bit_end_phase),
    .sf_valid(sf_valid), .sf_id(sf_id), .sf_sow(sf_sow), .sf_start_ms(sf_start_ms),
    .sf_info(sf_info), .sf_fixes(sf_fixes), .sf_inverted(sf_inverted),
    .sf_raw(sf_raw), .sf_word_fixes(sf_word_fixes), .sf_word_samples(sf_word_samples),
    .sf_word_phases(sf_word_phases), .sf_word_ms(sf_word_ms),
    .frame_synced(frame_synced),     .anchor_valid(anchor_valid),
    .anchor_ms(anchor_ms), .anchor_sow(anchor_sow), .week(week), .week_valid(week_valid),
    .sf_err(sf_err));

endmodule
