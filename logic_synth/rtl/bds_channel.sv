`include "b1i_params.svh"
// Independent configuration, PRN generation, acquisition, tracking and NH state.
module bds_channel #(
  parameter int ACQ_LANES = 64,
  parameter int BUF_DEPTH = 33024,
  parameter int PULLIN_MS = 2000
) (
  input logic clk, rst_n,
  input logic signed [2:0] sample,
  input logic cfg_write, cfg_enable,
  input logic [5:0] cfg_prn,
  input logic signed [31:0] cfg_dop_min, cfg_dop_step,
  input logic [7:0] cfg_bins,
  output logic capture_ok, bit_sync_ok, nav_data, nav_valid
);
  typedef enum logic [2:0] {OFF, RESTART, GEN_START, GEN_WAIT,
                           ACQ_START, SEARCH, TRACK} state_t;
  state_t state;
  logic [5:0] prn;
  logic signed [31:0] dop_min, dop_step;
  logic [7:0] n_bins;
  logic gen_busy, gen_done, gen_we, gen_chip;
  logic [10:0] gen_addr;
  logic acq_done, acq_found, acq_ready;
  logic [47:0] ho_phase;
  logic [31:0] ho_carrier;
  logic signed [31:0] res_dop;
  logic locked, saw_lock, dump_valid, dump_partial;
  logic [31:0] dump_ms;
  logic signed [25:0] prompt_i;
  logic nh_synced, nh_valid, nh_bit;
  logic [31:0] pullin_ms;
  wire handover = state == SEARCH && acq_ready && acq_found && !cfg_write;
  // Configuration takes effect on its sampling edge. Do not combinationally
  // truncate a previous nav_valid pulse when cfg_valid is presented mid-cycle.
  wire running = state == TRACK;
  wire code_we = gen_we && state == GEN_WAIT && !cfg_write;
  wire signed [47:0] aid = 48'((45'(res_dop) * 45'sd2749) >>> CODE_AID_SHIFT);
  wire [47:0] code_inc = CODE_NCO_INC_NOMINAL + aid;
  wire [48:0] ho_next = {1'b0, ho_phase} + {1'b0, code_inc};
  // Loading tracking consumes the current IF edge. Compensate that one sample
  // locally; the shared stream and the other five channels continue untouched.
  wire [47:0] init_phase = ho_next >= {1'b0, CODE_NCO_PERIOD}
                        ? ho_next[47:0] - CODE_NCO_PERIOD : ho_next[47:0];

  prn_code_gen u_gen (
    .clk(clk), .rst_n(rst_n), .start(state == GEN_START && !cfg_write), .prn(prn),
    .busy(gen_busy), .done(gen_done), .bad_prn(),
    .out_we(gen_we), .out_addr(gen_addr), .out_chip(gen_chip));

  // The public IF interface guarantees the four odd levels. This saves one
  // replay bit/sample without reducing the integration window or precision.
  bds_acquisition #(.N_LANES(ACQ_LANES), .BUF_DEPTH(BUF_DEPTH), .IF2_ONLY(1'b1)) u_acq (
    .clk(clk), .rst_n(rst_n), .sample_valid(1'b1), .sample(sample),
    .code_we(code_we), .code_waddr(gen_addr), .code_wdata(gen_chip),
    .start(state == ACQ_START && !cfg_write),
    .abort(cfg_write || state == OFF || state == RESTART), .ack(handover),
    .dop_min(dop_min), .dop_step(dop_step), .n_bins(n_bins),
    .nc(2'd2), .thr(8'd56), .busy(), .done(acq_done), .found(acq_found),
    .ready(acq_ready), .input_pause(), .ho_phase(ho_phase), .ho_carrier(ho_carrier),
    .res_dop(res_dop), .res_h(), .res_peak(), .res_mean());

  tracking_channel u_track (
    .clk(clk), .rst_n(rst_n), .enable(running), .sample_valid(1'b1), .sample(sample),
    .code_we(code_we), .code_waddr(gen_addr), .code_wdata(gen_chip),
    .init_load(handover || cfg_write),
    .init_code_phase(handover ? init_phase : 48'd0),
    .init_carrier_phase(handover ? ho_carrier + FREQ_WORD_IF + res_dop : 32'd0),
    .init_doppler(handover ? res_dop : 32'sd0),
    .code_spacing(4'(CODE_SPACING_DEFAULT)), .fll_en(!saw_lock),
    .pll_kp(16'(PLL_KP_DEFAULT)), .pll_ki(16'(PLL_KI_DEFAULT)),
    .fll_k(16'(FLL_K_DEFAULT)), .dll_kp(16'(DLL_KP_DEFAULT)), .dll_ki(16'(DLL_KI_DEFAULT)),
    .dump_valid(dump_valid), .dump_partial(dump_partial), .dump_ms(dump_ms),
    .i_e(), .q_e(), .i_p(prompt_i), .q_p(), .i_l(), .q_l(),
    .code_phase(), .code_phase_full(), .code_phase_after_sample(), .carrier_phase(),
    .ms_count(), .epoch_tick(), .freq_word(), .dop_word(), .locked(locked),
    .lock_cnt(), .d_pll_dbg(), .d_fll_dbg(), .d_dll_dbg());

  nh_bit_sync u_nh (
    .clk(clk), .rst_n(rst_n), .clear(!running),
    .dump_valid(dump_valid && running), .dump_partial(dump_partial),
    .dump_ms(dump_ms), .i_p(prompt_i), .dump_sample_count(64'd0), .dump_code_phase(48'd0),
    .synced(nh_synced), .bit_phase(), .bit_valid(nh_valid), .bit_val(nh_bit),
    .bit_ms(), .bit_mag(), .bit_end_sample(), .bit_end_phase());

  // Serial D1 bits have NH removed; Costas 180-degree ambiguity is retained.
  // No subframe/BCH interface is required by the synthesis assignment.
  assign bit_sync_ok = running && nh_synced;
  assign nav_valid = running && nh_synced && nh_valid;
  assign nav_data = nh_bit;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= OFF; prn <= '0; dop_min <= '0; dop_step <= '0; n_bins <= '0;
      capture_ok <= 1'b0; saw_lock <= 1'b0; pullin_ms <= '0;
    end else if (cfg_write) begin
      prn <= cfg_prn; dop_min <= cfg_dop_min; dop_step <= cfg_dop_step; n_bins <= cfg_bins;
      state <= cfg_enable && cfg_prn != 0 && cfg_bins != 0 ? RESTART : OFF;
      capture_ok <= 1'b0; saw_lock <= 1'b0; pullin_ms <= '0;
    end else begin
      case (state)
        OFF: capture_ok <= 1'b0;
        RESTART: if (!gen_busy) state <= GEN_START;
        GEN_START: state <= GEN_WAIT;
        GEN_WAIT: if (gen_done) state <= ACQ_START;
        ACQ_START: state <= SEARCH;
        SEARCH: begin
          if (handover) begin
            state <= TRACK; capture_ok <= 1'b1; saw_lock <= 1'b0; pullin_ms <= '0;
          end else if (acq_done && !acq_found) state <= ACQ_START;
        end
        TRACK: begin
          if (locked) saw_lock <= 1'b1;
          if (dump_valid && !dump_partial && !saw_lock) pullin_ms <= pullin_ms + 32'd1;
          if ((saw_lock && !locked) || (!saw_lock && pullin_ms >= PULLIN_MS)) begin
            state <= RESTART; capture_ok <= 1'b0; saw_lock <= 1'b0; pullin_ms <= '0;
          end
        end
        default: begin state <= OFF; capture_ok <= 1'b0; end
      endcase
    end
  end
endmodule
