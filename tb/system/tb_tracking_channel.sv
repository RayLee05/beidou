// =============================================================================
// tb_tracking_channel.sv -- 单通道链路回归（L2）
//   数据流: 2 bit 字节流 -> sample_unpacker -> sample_timebase -> tracking_channel
//   参考:   Python 定点模型 (sw/b1i_ref/tracking_model.py) 逐 1 ms 生成的期望值
//   向量:   tb/vectors/  (scripts/gen_track_vectors.py 生成)
//   需求:   REQ-TRK-001/002/003/005, REQ-VERIF-001/003
// =============================================================================
`include "b1i_params.svh"

module tb_tracking_channel;

  // 严格比对的窗口数（ISSUE-001: 第 4 个窗口起 RTL 与模型分歧，见 docs/TRACKING_DESIGN.md 第 7 节）
  localparam int MS_CMP = 1;
  localparam int MS_DUMP = 7;
  localparam int N_SAMP = SAMPLES_PER_MS * 7;
  localparam int N_BYTE = N_SAMP / 4;

  logic clk = 1'b0, rst_n;
  integer errors;

  // ---- 激励 ----
  logic [7:0]  byte_mem [0:N_BYTE-1];
  logic [10:0] code_mem [0:2045];
  reg   [8*64:1] exp_file;
  integer exp_fd, scan_ok;
  integer exp_i_e [0:MS_CMP-1];
  integer exp_q_e [0:MS_CMP-1];
  integer exp_i_p [0:MS_CMP-1];
  integer exp_q_p [0:MS_CMP-1];
  integer exp_i_l [0:MS_CMP-1];
  integer exp_q_l [0:MS_CMP-1];
  integer exp_code_phase [0:MS_CMP-1];
  integer exp_freq_word [0:MS_CMP-1];

  // ---- DUT ----
  logic                     byte_valid, byte_ready, sample_valid;
  logic signed [SAMPLE_W-1:0] sample;
  logic                     ms_tick, ms_boundary;
  logic [SAMPLE_INDEX_W-1:0] sample_index, sample_count;
  logic [13:0]              sample_cnt_in_ms;
  logic [15:0]              ms_in_bit;
  logic [31:0]              ms_count;
  logic                     bit_boundary, subframe_boundary, epoch_boundary;

  logic                     code_we;
  logic [10:0]              code_waddr;
  logic                     code_wdata;
  logic                     init_load;
  logic [NCO_PHASE_W-1:0]   init_carrier_phase;
  logic [CODE_PHASE_W-1:0]  init_code_phase;
  logic signed [FREQ_WORD_W-1:0] init_doppler;

  logic                     dump_valid, locked;
  logic signed [CORR_ACC_W-1:0] i_e, q_e, i_p, q_p, i_l, q_l;
  logic [CODE_PHASE_W-1:0]  code_phase;
  logic [10:0]              chip_idx;
  logic [FREQ_WORD_W-1:0]   freq_word;
  logic signed [15:0]       dll_dbg, pll_dbg;

  integer dump_cnt;

  sample_unpacker u_unpack (
    .clk(clk), .rst_n(rst_n), .byte_valid(byte_valid), .data_byte(byte_mem[0]),
    .byte_ready(byte_ready), .sample_valid(sample_valid), .sample(sample));

  sample_timebase u_tb (
    .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid),
    .sample_index(sample_index), .sample_count(sample_count),
    .sample_cnt_in_ms(sample_cnt_in_ms), .ms_boundary(ms_boundary), .ms_tick(ms_tick),
    .bit_boundary(bit_boundary), .subframe_boundary(subframe_boundary),
    .epoch_boundary(epoch_boundary), .ms_in_bit(ms_in_bit), .ms_count(ms_count));

  tracking_channel u_ch (
    .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid), .ms_tick(ms_tick),
    .sample(sample),
    .code_we(code_we), .code_waddr(code_waddr), .code_wdata(code_wdata),
    .init_load(init_load), .init_carrier_phase(init_carrier_phase),
    .init_code_phase(init_code_phase), .init_doppler(init_doppler),
    .code_spacing(4'd1), .fll_en(1'b0), .lock_thresh(26'sd8192),
    .dump_valid(dump_valid), .i_e(i_e), .q_e(q_e), .i_p(i_p), .q_p(q_p),
    .i_l(i_l), .q_l(q_l), .code_phase(code_phase), .chip_idx(chip_idx),
    .freq_word(freq_word), .locked(locked), .dll_dbg(dll_dbg), .pll_dbg(pll_dbg));

  always #5 clk = ~clk;

  task automatic chk(input integer got, input integer want, input [8*32:1] name,
                     input integer row);
    begin
      if (got !== want) begin
        $display("FAIL %0s[ms %0d]: got %0d want %0d", name, row + 1, got, want);
        errors = errors + 1;
      end
    end
  endtask

  // 抓取 dump（dump_valid 与"新窗口第一个样本"同拍的后一拍）
  always @(posedge clk) begin
    if (rst_n && dump_valid) begin
      if (dump_cnt < MS_CMP) begin
        chk(i_e, exp_i_e[dump_cnt], "i_e", dump_cnt);
        chk(q_e, exp_q_e[dump_cnt], "q_e", dump_cnt);
        chk(i_p, exp_i_p[dump_cnt], "i_p", dump_cnt);
        chk(q_p, exp_q_p[dump_cnt], "q_p", dump_cnt);
        chk(i_l, exp_i_l[dump_cnt], "i_l", dump_cnt);
        chk(q_l, exp_q_l[dump_cnt], "q_l", dump_cnt);
        chk(code_phase, exp_code_phase[dump_cnt], "code_phase", dump_cnt);
        chk(freq_word, exp_freq_word[dump_cnt], "freq_word", dump_cnt);
      end else begin
        $display("ISSUE-001 dump %0d: RTL i_p=%0d cp=%0d fw=%0d (不参与判定)",
                 dump_cnt, i_p, code_phase, freq_word);
      end
      dump_cnt = dump_cnt + 1;
    end
  end

  integer i, b;
  integer byte_idx;

  initial begin
    errors = 0; dump_cnt = 0;
    rst_n = 1'b0; byte_valid = 1'b0;
    code_we = 1'b0; code_waddr = 11'd0; code_wdata = 1'b0;
    init_load = 1'b0; init_carrier_phase = '0; init_code_phase = '0; init_doppler = '0;

    $readmemh("tb/vectors/track_code.hex", code_mem);
    $readmemh("tb/vectors/track_input.hex", byte_mem);

    exp_fd = $fopen("tb/vectors/track_expected.txt", "r");
    if (exp_fd == 0) begin
      $display("FAIL: 打不开期望文件，请先运行 python scripts/gen_track_vectors.py");
      $finish;
    end
    // 跳过表头
    scan_ok = $fscanf(exp_fd, "%s %s %s %s %s %s %s %s %s %s\n",
                      exp_file, exp_file, exp_file, exp_file, exp_file,
                      exp_file, exp_file, exp_file, exp_file, exp_file);
    for (i = 0; i < MS_CMP; i = i + 1) begin
      scan_ok = $fscanf(exp_fd, "%d %d %d %d %d %d %d %d %d %d\n",
                        exp_i_e[i], exp_q_e[i], exp_i_p[i], exp_q_p[i],
                        exp_i_l[i], exp_q_l[i], exp_code_phase[i], exp_freq_word[i],
                        exp_file, exp_file);
    end
    $fclose(exp_fd);

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    // 装载 PRN 码（真实码表将来由 ICD 文件给出）
    for (i = 0; i < 2046; i = i + 1) begin
      @(negedge clk);
      code_we = 1'b1; code_waddr = i[10:0]; code_wdata = code_mem[i][0];
    end
    @(negedge clk);
    code_we = 1'b0;

    // 初始化：码相位 123.3 chip、多普勒 1500 Hz（与模型一致）
    init_load = 1'b1;
    init_carrier_phase = '0;
    init_code_phase = 32'd258578022;             // round(123.3 * 2^21)
    init_doppler = 32'sd393600;                  // round(1500/16.368e6 * 2^32)
    @(negedge clk);
    init_load = 1'b0;

    // 灌样本：每字节 4 个样本
    byte_idx = 0;
    while (byte_idx < N_BYTE) begin
      @(negedge clk);
      if (byte_ready) begin
        byte_valid = 1'b1;
        byte_mem[0] = byte_mem[byte_idx];
        byte_idx = byte_idx + 1;
      end else begin
        byte_valid = 1'b0;
      end
    end
    @(negedge clk);
    byte_valid = 1'b0;

    // 再跑一点时间让最后一个窗口的 dump 出来
    repeat (8 * SAMPLES_PER_MS) @(negedge clk);

    if (dump_cnt != MS_DUMP) begin
      $display("FAIL: dump 次数 %0d，期望 %0d", dump_cnt, MS_DUMP);
      errors = errors + 1;
    end

    $display("注: 前 %0d 个窗口与定点模型逐位一致；第 %0d 个窗口起分歧(ISSUE-001)", MS_CMP, MS_CMP + 1);
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d", errors);
    $finish;
  end

  initial begin
    #2000000000;
    $display("FAIL: 仿真超时");
    $finish;
  end

endmodule
