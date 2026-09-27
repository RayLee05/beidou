// tb_sample_timebase.sv -- 公共时基单元测试（1 ms / 20 ms / 6 s / 1 s 边界）
`include "b1i_params.svh"

module tb_sample_timebase;

  logic clk = 1'b0, rst_n;
  logic sample_valid;
  logic [SAMPLE_INDEX_W-1:0] sample_index, sample_count;
  logic [13:0] sample_cnt_in_ms;
  logic ms_boundary, ms_tick, bit_boundary, subframe_boundary, epoch_boundary;
  logic [15:0] ms_in_bit;
  logic [31:0] ms_count;

  integer errors, i;
  integer ms_b_cnt, bit_b_cnt;

  sample_timebase dut (
    .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid),
    .sample_index(sample_index), .sample_count(sample_count),
    .sample_cnt_in_ms(sample_cnt_in_ms), .ms_boundary(ms_boundary), .ms_tick(ms_tick),
    .bit_boundary(bit_boundary), .subframe_boundary(subframe_boundary),
    .epoch_boundary(epoch_boundary), .ms_in_bit(ms_in_bit), .ms_count(ms_count));

  always #5 clk = ~clk;

  // 每拍采一次（sample_valid 恒 1）
  always @(posedge clk) begin
    if (rst_n && sample_valid) begin
      if (ms_boundary) ms_b_cnt = ms_b_cnt + 1;
      if (bit_boundary) bit_b_cnt = bit_b_cnt + 1;
    end
  end

  initial begin
    errors = 0; ms_b_cnt = 0; bit_b_cnt = 0;
    sample_valid = 1'b0; rst_n = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    sample_valid = 1'b1;

    // 观察 20 ms + 1 个样本
    for (i = 0; i < (20 * 16384 + 1); i = i + 1) @(posedge clk);
    #1;

    // 边界计数与"复位后第一个有效样本"的对齐有关：20 ms+1 个样本应出现 20 或 21 次
    if (ms_b_cnt < 20 || ms_b_cnt > 21) begin
      $display("FAIL: ms_boundary 次数应在 20..21，实际 %0d", ms_b_cnt);
      errors = errors + 1;
    end
    if (bit_b_cnt < 1 || bit_b_cnt > 2) begin
      $display("FAIL: bit_boundary 次数应在 1..2，实际 %0d", bit_b_cnt);
      errors = errors + 1;
    end
    if (ms_count != 20) begin
      $display("FAIL: ms_count 应为 20，实际 %0d", ms_count);
      errors = errors + 1;
    end
    // 计数器在复位释放那一拍可能已经计入一个样本，允许 ±1
    if (sample_count < 20 * 16384 || sample_count > 20 * 16384 + 2) begin
      $display("FAIL: sample_count 应在 %0d..%0d，实际 %0d", 20*16384, 20*16384+2, sample_count);
      errors = errors + 1;
    end

    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d", errors);
    $finish;
  end

  initial begin
    #200000000;
    $display("FAIL: 仿真超时");
    $finish;
  end

endmodule
