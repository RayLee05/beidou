`timescale 1ns/1ps
// Single-satellite tracking against the student BDI source.
// The receiver is tracking_channel. It sees only if_sample and if_valid.
// Source dbg_* ports stay open and are not inputs to the receiver.
`include "b1i_params.svh"

module tb_single_sat_track;
  localparam integer SAMPLES_PER_MS = 16368;
  localparam integer RUN_MS         = 640;
  localparam integer RUN_SAMPLES    = RUN_MS * SAMPLES_PER_MS;
  localparam integer STEADY_MS      = 100;
  localparam integer TRUE_DOP       = 65600;   // +250 Hz
  localparam integer INIT_DOP       = 39360;   // about +150 Hz, 100 Hz low
  localparam integer DOP_TOL        = 3936;    // 15 Hz in NCO words
  localparam integer EL_LIMIT       = 100;     // |E-L|/(E+L) < 0.10
  localparam integer IQ_LIMIT       = 100;     // |Q|/(|I|+1) < 0.10
  // First valid sample lands 0.15 chip after phase 10.
  // A 0.3 chip start winds the slow DLL integrator enough to leave a code-rate bias.
  // phase_init = (10<<37) + round(0.15*2^37) - (2^34 + ((39360*2749)>>16))
  localparam logic [47:0] INIT_CODE_PHASE = 48'd1377825506906;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic source_rst_n = 1'b0;
  logic prn_start = 1'b0;
  logic init_load = 1'b0;
  logic signed [1:0] if_sample;
  logic if_valid;
  logic signed [SAMPLE_W-1:0] sample;
  logic code_we;
  logic [10:0] code_waddr;
  logic code_bit;
  logic prn_busy, prn_done, bad_prn;

  logic dump_valid, dump_partial, locked, epoch_tick;
  logic [31:0] dump_ms, ms_count;
  logic signed [CORR_ACC_W-1:0] i_e, q_e, i_p, q_p, i_l, q_l;
  logic [CODE_PHASE_W-1:0] code_phase;
  logic [CODE_NCO_W-1:0] code_phase_full, code_phase_after_sample;
  logic [NCO_PHASE_W-1:0] carrier_phase;
  logic [FREQ_WORD_W-1:0] freq_word;
  logic signed [FREQ_WORD_W-1:0] dop_word;
  logic [3:0] lock_cnt;
  logic signed [15:0] d_pll, d_fll, d_dll;

  integer valid_samples = 0;
  integer full_dumps = 0;
  integer streak = 0;
  integer mag_e = 0, mag_p = 0, mag_l = 0;
  integer el_permille = 0, iq_permille = 0;
  integer dop_hz = 0;
  integer trace_file = 0;
  integer dop_delta = 0;
  integer saw_code_error = 0;

  always #30.54740958 clk = ~clk;

  assign sample = {if_sample[1], if_sample};

  bdi_signal_source_doppler #(
    .PRN_PHASE_OFFSET(10),
    .PRN_WARMUP_CHIPS(4),
    .DOPPLER_FCW(32'sd65600),
    .CODE_DOPPLER_FCW(32'sd86)
  ) u_source (
    .clk_16m368(clk),
    .rst_n(source_rst_n),
    .enable(1'b1),
    .if_sample(if_sample),
    .if_valid(if_valid),
    .dbg_nav_bit(),
    .dbg_nh_bit(),
    .dbg_prn_bit(),
    .dbg_prn_phase(),
    .dbg_nh_idx(),
    .dbg_nav_idx(),
    .dbg_carrier_phase(),
    .dbg_carrier_lut_index(),
    .dbg_code_nco_phase(),
    .dbg_code_fcw(),
    .dbg_code_chip_tick()
  );

  prn_code_gen u_prn (
    .clk(clk), .rst_n(rst_n), .start(prn_start), .prn(6'd6),
    .busy(prn_busy), .done(prn_done), .bad_prn(bad_prn),
    .out_we(code_we), .out_addr(code_waddr), .out_chip(code_bit)
  );

  tracking_channel u_track (
    .clk(clk), .rst_n(rst_n), .enable(1'b1),
    .sample_valid(if_valid), .sample(sample),
    .code_we(code_we), .code_waddr(code_waddr), .code_wdata(code_bit),
    .init_load(init_load), .init_carrier_phase(32'd0),
    .init_code_phase(INIT_CODE_PHASE), .init_doppler(INIT_DOP),
    .code_spacing(4'(CODE_SPACING_DEFAULT)), .fll_en(1'b1),
    .pll_kp(16'(PLL_KP_DEFAULT)), .pll_ki(16'(PLL_KI_DEFAULT)),
    .fll_k(16'(FLL_K_DEFAULT)),
    .dll_kp(16'(DLL_KP_DEFAULT)), .dll_ki(16'(DLL_KI_DEFAULT)),
    .dump_valid(dump_valid), .dump_partial(dump_partial), .dump_ms(dump_ms),
    .i_e(i_e), .q_e(q_e), .i_p(i_p), .q_p(q_p), .i_l(i_l), .q_l(q_l),
    .code_phase(code_phase), .code_phase_full(code_phase_full),
    .code_phase_after_sample(code_phase_after_sample),
    .carrier_phase(carrier_phase), .ms_count(ms_count), .epoch_tick(epoch_tick),
    .freq_word(freq_word), .dop_word(dop_word), .locked(locked), .lock_cnt(lock_cnt),
    .d_pll_dbg(d_pll), .d_fll_dbg(d_fll), .d_dll_dbg(d_dll)
  );

  function automatic integer corr_abs(input logic signed [CORR_ACC_W-1:0] v);
    corr_abs = (v < 0) ? integer'(-v) : integer'(v);
  endfunction

  always @(posedge clk) begin
    #0.001;
    if (source_rst_n && if_valid)
      valid_samples = valid_samples + 1;

    if (rst_n && dump_valid && !dump_partial) begin
      mag_e = corr_abs(i_e) + corr_abs(q_e);
      mag_p = corr_abs(i_p) + corr_abs(q_p);
      mag_l = corr_abs(i_l) + corr_abs(q_l);
      if ((mag_e + mag_l) > 0)
        el_permille = integer'(((mag_e > mag_l)
          ? (longint'(mag_e) - longint'(mag_l))
          : (longint'(mag_l) - longint'(mag_e))) * 64'sd1000
          / (longint'(mag_e) + longint'(mag_l)));
      else
        el_permille = 1000;
      iq_permille = integer'((longint'(corr_abs(q_p)) * 64'sd1000)
        / (longint'(corr_abs(i_p)) + 64'sd1));
      dop_hz = integer'((longint'(dop_word) * 64'sd16368000) / 64'sd4294967296);
      dop_delta = integer'(dop_word) - TRUE_DOP;
      if (dop_delta < 0)
        dop_delta = -dop_delta;

      if (full_dumps == 0) begin
        if (mag_p < 1000)
          $fatal(1, "prompt amplitude too small on first dump: %0d", mag_p);
        if (el_permille <= EL_LIMIT)
          $fatal(1, "initial code error not visible: el_permille=%0d P=%0d E=%0d L=%0d",
            el_permille, mag_p, mag_e, mag_l);
        if (dop_word !== INIT_DOP)
          $fatal(1, "initial doppler word is %0d, expected %0d", dop_word, INIT_DOP);
        saw_code_error = 1;
      end

      if ((mag_p > mag_e) && (mag_p > mag_l) &&
          (el_permille < EL_LIMIT) && (iq_permille < IQ_LIMIT) &&
          (dop_delta < DOP_TOL))
        streak = streak + 1;
      else
        streak = 0;

      $fdisplay(trace_file, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
        full_dumps, mag_e, mag_p, mag_l, el_permille, i_p, q_p, iq_permille,
        dop_word, dop_hz, d_pll, d_dll, d_fll, locked);
      if (full_dumps < 3 || (full_dumps % 50) == 0)
        $display("dump %0d: P=%0d E=%0d L=%0d el=%0d I=%0d Q=%0d iq=%0d dop=%0d Hz=%0d locked=%0d streak=%0d",
          full_dumps, mag_p, mag_e, mag_l, el_permille, i_p, q_p, iq_permille,
          dop_word, dop_hz, locked, streak);
      full_dumps = full_dumps + 1;
    end
  end

  initial begin
    string csv_path;
    if (!$value$plusargs("CSV=%s", csv_path))
      csv_path = "track.csv";
    trace_file = $fopen(csv_path, "w");
    if (!trace_file)
      $fatal(1, "cannot open %s", csv_path);
    $fdisplay(trace_file,
      "dump,mag_e,mag_p,mag_l,el_permille,i_p,q_p,iq_permille,dop_word,dop_hz,d_pll,d_dll,d_fll,locked");

    repeat (8) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    prn_start = 1'b1;
    @(posedge clk);
    prn_start = 1'b0;
    wait (prn_done);
    if (bad_prn)
      $fatal(1, "PRN 6 code generator failed");
    @(posedge clk);
    init_load = 1'b1;
    @(posedge clk);
    init_load = 1'b0;
    @(posedge clk);
    source_rst_n = 1'b1;

    wait (valid_samples >= RUN_SAMPLES);
    #0.002;
    if (!saw_code_error)
      $fatal(1, "never observed the initial code error");
    if (valid_samples < 500 * SAMPLES_PER_MS)
      $fatal(1, "simulation shorter than 500 ms: %0d samples", valid_samples);
    if (full_dumps < STEADY_MS)
      $fatal(1, "too few full dumps: %0d", full_dumps);
    if (streak < STEADY_MS)
      $fatal(1, "steady tracking did not hold for %0d ms (streak=%0d el=%0d iq=%0d dop=%0d Hz=%0d)",
        STEADY_MS, streak, el_permille, iq_permille, dop_word, dop_hz);

    $fclose(trace_file);
    $display("PASS: single satellite tracking; full_dumps=%0d valid_samples=%0d streak=%0d dop_word=%0d dop_hz=%0d el_permille=%0d iq_permille=%0d",
      full_dumps, valid_samples, streak, dop_word, dop_hz, el_permille, iq_permille);
    $finish;
  end

  initial begin
    #900_000_000;
    $fatal(1, "tracking timeout, valid_samples=%0d full_dumps=%0d", valid_samples, full_dumps);
  end
endmodule
