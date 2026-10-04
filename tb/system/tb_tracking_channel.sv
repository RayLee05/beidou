// =============================================================================
// tb_tracking_channel.sv -- 单通道链路回归（L2，逐位比对）
//   数据流: 2 bit 字节流 -> sample_unpacker -> tracking_channel
//   参考:   sw/b1i_ref/tracking_model.py（scripts/gen_track_vectors.py 生成期望值）
//   比对:   每个码周期 dump 的 E/P/L、码相位、下一窗口频率字、多普勒积分、锁定与鉴别器
//   需求:   REQ-TRK-001/002/003/005/006, REQ-VERIF-001/003
// =============================================================================
`include "b1i_params.svh"

module tb_tracking_channel;

  localparam int MAX_BYTES = 2_000_000;
  localparam int MAX_WIN   = 2000;

  logic clk = 1'b0, rst_n;
  always #5 clk = ~clk;

  // ---- 向量 ----
  logic [7:0]  byte_mem [0:MAX_BYTES-1];
  logic [0:0]  code_mem [0:2045];
  logic [47:0] init_mem [0:3];
  integer exp_ms[0:MAX_WIN-1], exp_part[0:MAX_WIN-1];
  integer exp_ie[0:MAX_WIN-1], exp_qe[0:MAX_WIN-1], exp_ip[0:MAX_WIN-1];
  integer exp_qp[0:MAX_WIN-1], exp_il[0:MAX_WIN-1], exp_ql[0:MAX_WIN-1];
  logic [31:0] exp_cp[0:MAX_WIN-1], exp_fw[0:MAX_WIN-1];
  integer exp_dop[0:MAX_WIN-1], exp_lk[0:MAX_WIN-1], exp_lc[0:MAX_WIN-1];
  integer exp_dp[0:MAX_WIN-1], exp_df[0:MAX_WIN-1], exp_dd[0:MAX_WIN-1];
  integer n_bytes, n_win;

  // ---- DUT ----
  logic                        byte_valid, byte_ready, sample_valid;
  logic [7:0]                  data_byte;
  logic signed [SAMPLE_W-1:0]  sample;
  logic                        code_we, init_load;
  logic [10:0]                 code_waddr;
  logic                        code_wdata;
  logic [CODE_NCO_W-1:0]       init_code_phase;
  logic signed [31:0]          init_doppler;

  logic                        dump_valid, dump_partial, locked, epoch_tick;
  logic [31:0]                 dump_ms, ms_count;
  logic signed [CORR_ACC_W-1:0] i_e, q_e, i_p, q_p, i_l, q_l;
  logic [CODE_PHASE_W-1:0]     code_phase;
  logic [FREQ_WORD_W-1:0]      freq_word;
  logic signed [31:0]          dop_word;
  logic [3:0]                  lock_cnt;
  logic signed [15:0]          d_pll, d_fll, d_dll;

  sample_unpacker u_unpack (
    .clk(clk), .rst_n(rst_n), .byte_valid(byte_valid), .data_byte(data_byte),
    .byte_ready(byte_ready), .sample_valid(sample_valid), .sample(sample));

  tracking_channel u_ch (
    .clk(clk), .rst_n(rst_n), .enable(1'b1), .sample_valid(sample_valid), .sample(sample),
    .code_we(code_we), .code_waddr(code_waddr), .code_wdata(code_wdata),
    .init_load(init_load), .init_carrier_phase(32'd0), .init_code_phase(init_code_phase),
    .init_doppler(init_doppler),
    .code_spacing(4'(CODE_SPACING_DEFAULT)), .fll_en(1'b1),
    .pll_kp(16'(PLL_KP_DEFAULT)), .pll_ki(16'(PLL_KI_DEFAULT)), .fll_k(16'(FLL_K_DEFAULT)),
    .dll_kp(16'(DLL_KP_DEFAULT)), .dll_ki(16'(DLL_KI_DEFAULT)),
    .dump_valid(dump_valid), .dump_partial(dump_partial), .dump_ms(dump_ms),
    .i_e(i_e), .q_e(q_e), .i_p(i_p), .q_p(q_p), .i_l(i_l), .q_l(q_l),
    .code_phase(code_phase), .ms_count(ms_count), .epoch_tick(epoch_tick),
    .freq_word(freq_word), .dop_word(dop_word), .locked(locked), .lock_cnt(lock_cnt),
    .d_pll_dbg(d_pll), .d_fll_dbg(d_fll), .d_dll_dbg(d_dll));

  // ---- 比对 ----
  integer errors = 0, dump_cnt = 0, shown = 0;

  task automatic chk(input longint got, input longint want, input string name, input integer row);
    if (got != want) begin
      if (shown < 40) $display("MISMATCH win %0d %s: rtl=%0d model=%0d", row, name, got, want);
      shown++;
      errors++;
    end
  endtask

  always @(posedge clk) begin
    if (rst_n && dump_valid) begin
      if (dump_cnt < n_win) begin
        chk(dump_ms, exp_ms[dump_cnt], "ms", dump_cnt);
        chk(dump_partial, exp_part[dump_cnt], "partial", dump_cnt);
        chk(i_e, exp_ie[dump_cnt], "i_e", dump_cnt);
        chk(q_e, exp_qe[dump_cnt], "q_e", dump_cnt);
        chk(i_p, exp_ip[dump_cnt], "i_p", dump_cnt);
        chk(q_p, exp_qp[dump_cnt], "q_p", dump_cnt);
        chk(i_l, exp_il[dump_cnt], "i_l", dump_cnt);
        chk(q_l, exp_ql[dump_cnt], "q_l", dump_cnt);
        chk(code_phase, exp_cp[dump_cnt], "code_phase", dump_cnt);
        chk(freq_word, exp_fw[dump_cnt], "freq_word", dump_cnt);
        chk(dop_word, exp_dop[dump_cnt], "dop_word", dump_cnt);
        chk(locked, exp_lk[dump_cnt], "locked", dump_cnt);
        chk(lock_cnt, exp_lc[dump_cnt], "lock_cnt", dump_cnt);
        chk(d_pll, exp_dp[dump_cnt], "d_pll", dump_cnt);
        chk(d_fll, exp_df[dump_cnt], "d_fll", dump_cnt);
        chk(d_dll, exp_dd[dump_cnt], "d_dll", dump_cnt);
        if (dump_cnt % 50 == 0)
          $display("win %4d: ip=%0d qp=%0d dop=%0d locked=%0d", dump_cnt, i_p, q_p, dop_word, locked);
      end
      dump_cnt++;
    end
  end

  // ---- 激励 ----
  integer fd, i, rc, byte_idx;
  string  hdr;

  initial begin
    rst_n = 1'b0; byte_valid = 1'b0; data_byte = 8'h00;
    code_we = 1'b0; code_waddr = '0; code_wdata = 1'b0; init_load = 1'b0;
    init_code_phase = '0; init_doppler = '0;

    $readmemh("tb/vectors/track_code.hex", code_mem);
    $readmemh("tb/vectors/track_init.hex", init_mem);
    n_bytes = init_mem[2];
    n_win   = init_mem[3];
    $readmemh("tb/vectors/track_input.hex", byte_mem, 0, n_bytes - 1);

    fd = $fopen("tb/vectors/track_expected.txt", "r");
    if (fd == 0) begin
      $display("TEST FAILED: cannot open track_expected.txt (run scripts/gen_track_vectors.py)");
      $finish;
    end
    rc = $fgets(hdr, fd);
    for (i = 0; i < n_win; i++) begin
      rc = $fscanf(fd, "%d %d %d %d %d %d %d %d %h %h %d %d %d %d %d %d\n",
                   exp_ms[i], exp_part[i], exp_ie[i], exp_qe[i], exp_ip[i], exp_qp[i],
                   exp_il[i], exp_ql[i], exp_cp[i], exp_fw[i], exp_dop[i], exp_lk[i],
                   exp_lc[i], exp_dp[i], exp_df[i], exp_dd[i]);
    end
    $fclose(fd);
    $display("vectors: %0d bytes, %0d windows", n_bytes, n_win);

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    for (i = 0; i < 2046; i++) begin
      @(negedge clk);
      code_we = 1'b1; code_waddr = i[10:0]; code_wdata = code_mem[i][0];
    end
    @(negedge clk);
    code_we = 1'b0;

    init_code_phase = init_mem[0];
    init_doppler    = init_mem[1][31:0];
    init_load = 1'b1;
    @(negedge clk);
    init_load = 1'b0;

    byte_idx = 0;
    while (byte_idx < n_bytes) begin
      @(negedge clk);
      if (byte_ready) begin
        byte_valid = 1'b1;
        data_byte  = byte_mem[byte_idx];
        byte_idx++;
      end else begin
        byte_valid = 1'b0;
      end
    end
    @(negedge clk);
    byte_valid = 1'b0;
    repeat (100) @(negedge clk);

    if (dump_cnt < n_win) begin
      $display("ERROR: only %0d dumps, expected %0d", dump_cnt, n_win);
      errors++;
    end
    $display("compared %0d windows, %0d mismatches, final locked=%0d", n_win, errors, locked);
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d", errors);
    $finish;
  end

endmodule
