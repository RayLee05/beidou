// tb_d1_frame_sync.sv -- 帧同步 / 极性 / 去交织 / BCH 纠错 / 字段提取
//   输入 7 个子帧（第 3 个含单比特错误；第 5 个子帧前 40 bit 起整体反相）。
//   期望输出子帧 0,1,2,4,5（子帧 3 的后续前导码被反相打断，子帧 6 之后没有前导码）。
`include "b1i_params.svh"

module tb_d1_frame_sync;

  logic clk = 1'b0, rst_n;
  always #5 clk = ~clk;

  logic [0:0]   bits [0:4095];
  integer       n_bits, n_sf, flip_at;
  integer       exp_start [0:7];
  integer       exp_id [0:7];
  integer       exp_sow [0:7];
  logic [223:0] exp_info [0:7];
  integer       want [0:4] = '{0, 1, 2, 4, 5};

  logic          bit_valid, bit_val;
  logic [31:0]   bit_ms;
  logic          sf_valid, sf_inverted, frame_synced, anchor_valid, week_valid;
  logic [2:0]    sf_id;
  logic [19:0]   sf_sow, anchor_sow;
  logic [31:0]   sf_start_ms, anchor_ms;
  logic [223:0]  sf_info;
  logic [4:0]    sf_fixes;
  logic [12:0]   week;

  d1_frame_sync dut (
    .clk(clk), .rst_n(rst_n), .clear(1'b0), .bit_valid(bit_valid), .bit_val(bit_val),
    .bit_ms(bit_ms), .sf_valid(sf_valid), .sf_id(sf_id), .sf_sow(sf_sow),
    .sf_start_ms(sf_start_ms), .sf_info(sf_info), .sf_fixes(sf_fixes),
    .sf_inverted(sf_inverted), .frame_synced(frame_synced), .anchor_valid(anchor_valid),
    .anchor_ms(anchor_ms), .anchor_sow(anchor_sow), .week(week), .week_valid(week_valid),
    .sf_err());

  localparam int MS0 = 1000;     // 第 0 个比特的 ms 标签
  integer errors = 0, got = 0, e, total_fixes = 0;

  always @(posedge clk) begin
    if (sf_valid) begin
      if (got >= 5) begin
        $display("ERROR: unexpected extra subframe id=%0d", sf_id);
        errors++;
      end else begin
        e = want[got];
        $display("subframe: id=%0d sow=%0d start_ms=%0d fixes=%0d inverted=%0d", sf_id, sf_sow,
                 sf_start_ms, sf_fixes, sf_inverted);
        if (sf_id != exp_id[e] || sf_sow != exp_sow[e]) begin
          $display("ERROR: id/sow mismatch, want %0d/%0d", exp_id[e], exp_sow[e]); errors++;
        end
        if (sf_start_ms != MS0 + 20 * exp_start[e]) begin
          $display("ERROR: start_ms want %0d", MS0 + 20 * exp_start[e]); errors++;
        end
        if (sf_info !== exp_info[e]) begin
          $display("ERROR: info mismatch"); errors++;
        end
        if (sf_inverted != (exp_start[e] >= flip_at)) begin
          $display("ERROR: polarity"); errors++;
        end
        total_fixes += sf_fixes;
      end
      got++;
    end
  end

  integer fd, rc, i;
  initial begin
    $readmemh("tb/vectors/nav_bits.hex", bits);
    fd = $fopen("tb/vectors/nav_expected.txt", "r");
    rc = $fscanf(fd, "%d %d %d\n", n_bits, n_sf, flip_at);
    for (i = 0; i < n_sf; i++)
      rc = $fscanf(fd, "%d %d %d %h\n", exp_start[i], exp_id[i], exp_sow[i], exp_info[i]);
    $fclose(fd);

    rst_n = 1'b0; bit_valid = 0; bit_val = 0; bit_ms = 0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    for (i = 0; i < n_bits; i++) begin
      repeat (30) @(negedge clk);
      bit_valid = 1; bit_val = bits[i][0]; bit_ms = MS0 + 20 * i;
      @(negedge clk);
      bit_valid = 0;
    end
    repeat (100) @(negedge clk);
    $display("%0d subframes, total BCH fixes %0d, week=%0d valid=%0d", got, total_fixes, week,
             week_valid);
    if (got != 5) begin $display("ERROR: expected 5 subframes"); errors++; end
    if (total_fixes < 1) begin $display("ERROR: injected bit error not corrected"); errors++; end
    if (!week_valid || week != 950) begin $display("ERROR: week"); errors++; end
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d", errors);
    $finish;
  end

endmodule
