// =============================================================================
// tb_acquisition.sv -- 捕获 -> 移交 -> 跟踪 端到端用例
//   1) prn_code_gen 同时写捕获码 RAM 与跟踪通道码 RAM（目标 PRN）
//   2) acquisition 截取、回放搜索、细搜、外推；ready 后在无样本拍装载 tracking_channel
//   3) 跟踪期间在每个 1 ms 网格点比对码相位真值；结束时要求已锁定且误差 < 0.1 chip
//   4) 再搜一个场景中不存在的 PRN，要求 found=0
//   时钟 100 MHz；字节按 16.368 MHz/4 的平均速率送入解包器（实时节拍）
// =============================================================================
`include "b1i_params.svh"

module tb_acquisition;

  localparam int MAX_BYTES = 3_000_000;
  localparam int MAX_MS    = 1000;

  logic clk = 1'b0, rst_n;
  always #5 clk = ~clk;

  logic [7:0]  byte_mem [0:MAX_BYTES-1];
  logic [31:0] cfg_mem [0:7];
  logic [31:0] truth_cp [0:MAX_MS-1];
  logic [31:0] truth_dw [0:MAX_MS-1];
  logic [63:0] truth_raw [0:MAX_MS-1];
  integer n_bytes;

  // ---- 样本源 ----
  logic        byte_valid, byte_ready, sample_valid;
  logic [7:0]  data_byte;
  logic signed [SAMPLE_W-1:0] sample;
  integer      byte_idx = 0;
  real         pace = 0.0;
  logic        feeding = 1'b0;
  longint      n_samp = 0;     // 已送出的样本数

  sample_unpacker u_unpack (
    .clk(clk), .rst_n(rst_n), .byte_valid(byte_valid), .data_byte(data_byte),
    .byte_ready(byte_ready), .sample_valid(sample_valid), .sample(sample));

  always @(posedge clk) if (sample_valid) n_samp <= n_samp + 1;

  always @(negedge clk) begin
    byte_valid <= 1'b0;
    if (feeding && byte_idx < n_bytes) begin
      pace = pace + 16.368 / 4.0 / 100.0;
      if (pace >= 1.0 && byte_ready) begin
        pace = pace - 1.0;
        byte_valid <= 1'b1;
        data_byte  <= byte_mem[byte_idx];
        byte_idx   <= byte_idx + 1;
      end
    end
  end

  // ---- PRN 码发生器（广播写两个码 RAM）----
  logic        gen_start, gen_busy, gen_done, gen_bad, gen_we, gen_chip;
  logic [5:0]  gen_prn;
  logic [10:0] gen_addr;
  prn_code_gen u_gen (
    .clk(clk), .rst_n(rst_n), .start(gen_start), .prn(gen_prn), .busy(gen_busy),
    .done(gen_done), .bad_prn(gen_bad), .out_we(gen_we), .out_addr(gen_addr), .out_chip(gen_chip));

  // ---- 捕获 ----
  logic        acq_start, acq_ack, acq_busy, acq_done, acq_found, acq_ready;
  logic [CODE_NCO_W-1:0] ho_phase;
  logic signed [31:0]    res_dop;
  logic [11:0]           res_h;
  logic [27:0]           res_peak, res_mean;
  acquisition #(.N_LANES(64), .BUF_DEPTH(33024)) u_acq (
    .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid), .sample(sample),
    .code_we(gen_we), .code_waddr(gen_addr), .code_wdata(gen_chip),
    .start(acq_start), .abort(1'b0), .ack(acq_ack),
    .dop_min(cfg_mem[2]), .dop_step(cfg_mem[3]), .n_bins(cfg_mem[4][7:0]),
    .nc(cfg_mem[5][1:0]), .thr(cfg_mem[6][7:0]),
    .busy(acq_busy), .done(acq_done), .found(acq_found), .ready(acq_ready),
    .ho_phase(ho_phase), .res_dop(res_dop), .res_h(res_h),
    .res_peak(res_peak), .res_mean(res_mean));

  // ---- 跟踪通道 ----
  logic        ch_we, init_load, ch_enable = 1'b0;
  logic        dump_valid, dump_partial, locked, epoch_tick;
  logic [31:0] dump_ms, ms_count;
  logic signed [CORR_ACC_W-1:0] i_e, q_e, i_p, q_p, i_l, q_l;
  logic [CODE_PHASE_W-1:0] code_phase;
  logic [FREQ_WORD_W-1:0]  freq_word;
  logic signed [31:0]      dop_word;
  logic [3:0]              lock_cnt;
  logic signed [15:0]      d_pll, d_fll, d_dll;
  logic                    fll_en = 1'b1;
  logic                    ch_code_sel = 1'b1;     // 只有目标 PRN 的码写入跟踪通道
  assign ch_we = gen_we & ch_code_sel;

  tracking_channel u_ch (
    .clk(clk), .rst_n(rst_n), .enable(ch_enable), .sample_valid(sample_valid), .sample(sample),
    .code_we(ch_we), .code_waddr(gen_addr), .code_wdata(gen_chip),
    .init_load(init_load), .init_carrier_phase(32'd0), .init_code_phase(ho_phase),
    .init_doppler(res_dop),
    .code_spacing(4'(CODE_SPACING_DEFAULT)), .fll_en(fll_en),
    .pll_kp(16'(PLL_KP_DEFAULT)), .pll_ki(16'(PLL_KI_DEFAULT)), .fll_k(16'(FLL_K_DEFAULT)),
    .dll_kp(16'(DLL_KP_DEFAULT)), .dll_ki(16'(DLL_KI_DEFAULT)),
    .dump_valid(dump_valid), .dump_partial(dump_partial), .dump_ms(dump_ms),
    .i_e(i_e), .q_e(q_e), .i_p(i_p), .q_p(q_p), .i_l(i_l), .q_l(q_l),
    .code_phase(code_phase), .ms_count(ms_count), .epoch_tick(epoch_tick),
    .freq_word(freq_word), .dop_word(dop_word), .locked(locked), .lock_cnt(lock_cnt),
    .d_pll_dbg(d_pll), .d_fll_dbg(d_fll), .d_dll_dbg(d_dll));

  // ---- 码相位真值比对（每个 1 ms 网格点）----
  integer errors = 0;
  real    cp_err, last_err = 99.0;
  logic   tracking = 1'b0;
  integer grid_cnt = 0;

  function automatic real wrap_chips(input real e);
    while (e > 1023.0)  e = e - 2046.0;
    while (e < -1023.0) e = e + 2046.0;
    return e;
  endfunction

  // 网格点 = 第 m*16368-1 个样本（0 起）；它处理完后的下一拍读取通道码相位
  logic grid_hit = 1'b0;
  longint grid_m;
  always @(posedge clk) begin
    grid_hit <= tracking && sample_valid && ((n_samp + 1) % SAMPLES_PER_MS == 0);
    if (tracking && sample_valid && ((n_samp + 1) % SAMPLES_PER_MS == 0))
      grid_m <= (n_samp + 1) / SAMPLES_PER_MS;
    if (grid_hit) begin
      cp_err = wrap_chips((real'(code_phase) - real'(truth_cp[grid_m - 1])) / 2097152.0);
      last_err = cp_err;
      if (grid_m % 50 == 0)
        $display("t=%0d ms: code err %8.4f chip  dop err %8.2f Hz  locked=%0d", grid_m, cp_err,
                 (real'(dop_word) - real'($signed(truth_dw[grid_m - 1]))) * 16.368e6 / 4294967296.0,
                 locked);
    end
  end

  // ---- 主流程 ----
  integer i, ho_ms;
  initial begin
    rst_n = 1'b0; gen_start = 0; gen_prn = 0; acq_start = 0; acq_ack = 0; init_load = 0;
    $readmemh("tb/vectors/acq_cfg.hex", cfg_mem);
    n_bytes = cfg_mem[7];
    $readmemh("tb/vectors/acq_input.hex", byte_mem, 0, n_bytes - 1);
    $readmemh("tb/vectors/acq_truth.hex", truth_raw);
    for (i = 0; i < MAX_MS; i++) begin
      truth_cp[i] = truth_raw[i][63:32];
      truth_dw[i] = truth_raw[i][31:0];
    end
    $display("target PRN %0d, absent PRN %0d, %0d bins, %0d bytes", cfg_mem[0], cfg_mem[1],
             cfg_mem[4], n_bytes);
    repeat (5) @(negedge clk);
    rst_n = 1'b1;
    feeding = 1'b1;

    // 码表
    @(negedge clk); gen_prn = cfg_mem[0][5:0]; gen_start = 1;
    @(negedge clk); gen_start = 0;
    wait (gen_done);

    // 捕获目标
    @(negedge clk); acq_start = 1;
    @(negedge clk); acq_start = 0;
    wait (acq_done);
    @(negedge clk);
    $display("acq done @%0d samples: found=%0d h=%0d dop=%0d peak=%0d mean=%0d",
             n_samp, acq_found, res_h, res_dop, res_peak, res_mean);
    if (!acq_found) begin
      $display("TEST FAILED: target not acquired");
      $finish;
    end
    // 在无样本的拍装载（ready 期间 ho_phase 实时跟随）
    @(negedge clk);
    while (sample_valid) @(negedge clk);
    init_load = 1; ch_enable = 1;
    @(negedge clk);
    init_load = 0; acq_ack = 1;
    @(negedge clk);
    acq_ack = 0;
    ho_ms = n_samp / SAMPLES_PER_MS;
    tracking = 1;
    $display("handover @%0d ms", ho_ms);

    // 跟踪 300 ms（FLL 辅助 200 ms 后关闭）
    wait (n_samp >= (ho_ms + 200) * SAMPLES_PER_MS);
    fll_en = 1'b0;
    wait (n_samp >= (ho_ms + 300) * SAMPLES_PER_MS);
    @(negedge clk);
    $display("after 300 ms tracking: locked=%0d code err=%0.4f chip", locked, last_err);
    if (!locked) begin $display("ERROR: not locked"); errors++; end
    if (last_err > 0.1 || last_err < -0.1) begin $display("ERROR: code error too large"); errors++; end

    // 缺席 PRN：应判未捕获
    ch_code_sel = 1'b0;
    @(negedge clk); gen_prn = cfg_mem[1][5:0]; gen_start = 1;
    @(negedge clk); gen_start = 0;
    wait (gen_done);
    @(negedge clk); acq_start = 1;
    @(negedge clk); acq_start = 0;
    wait (acq_done);
    @(negedge clk);
    $display("absent PRN %0d: found=%0d peak=%0d mean=%0d", cfg_mem[1], acq_found, res_peak, res_mean);
    if (acq_found) begin $display("ERROR: false acquisition"); errors++; end

    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d", errors);
    $finish;
  end

  initial begin
    #2_000_000_000;
    $display("TEST FAILED: timeout");
    $finish;
  end

endmodule
