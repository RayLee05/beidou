// tb_record_fifo.sv -- 记录 FIFO 入队/出队/满溢出
`include "b1i_params.svh"

module tb_record_fifo;

  logic clk = 1'b0, rst_n;
  always #5 clk = ~clk;

  logic         wr_valid, wr_ready, rd_valid, rd_ready, overflow;
  logic [255:0] wr_data, rd_data;
  logic [5:0]   count;

  record_fifo #(.DEPTH(4)) dut (
    .clk(clk), .rst_n(rst_n),
    .wr_valid(wr_valid), .wr_ready(wr_ready), .wr_data(wr_data),
    .rd_valid(rd_valid), .rd_ready(rd_ready), .rd_data(rd_data),
    .overflow(overflow), .count(count));

  integer errors = 0, i;
  logic [255:0] got [0:3];

  initial begin
    rst_n = 0; wr_valid = 0; wr_data = 0; rd_ready = 0;
    repeat (3) @(negedge clk);
    rst_n = 1;
    @(negedge clk);

    for (i = 0; i < 4; i++) begin
      if (!wr_ready) begin $display("FAIL: should accept %0d", i); errors++; end
      wr_valid = 1; wr_data = 256'(i + 1);
      @(negedge clk);
    end
    wr_valid = 0;
    if (wr_ready) begin $display("FAIL: full should not be ready"); errors++; end
    wr_valid = 1; wr_data = 256'hDEAD;
    @(negedge clk);
    if (!overflow) begin $display("FAIL: expected overflow"); errors++; end
    wr_valid = 0;
    @(negedge clk);
    if (overflow) begin $display("FAIL: overflow should pulse"); errors++; end

    for (i = 0; i < 4; i++) begin
      if (!rd_valid) begin $display("FAIL: empty too early"); errors++; end
      got[i] = rd_data;
      rd_ready = 1;
      @(negedge clk);
    end
    rd_ready = 0;
    if (rd_valid) begin $display("FAIL: should be empty"); errors++; end
    for (i = 0; i < 4; i++)
      if (got[i] !== 256'(i + 1)) begin
        $display("FAIL: data %0d got %h", i, got[i]); errors++;
      end

    // 再填满，满时同拍读+写应腾位且不报 overflow
    for (i = 0; i < 4; i++) begin
      wr_valid = 1; wr_data = 256'(8 + i);
      @(negedge clk);
    end
    wr_valid = 0;
    rd_ready = 1; wr_valid = 1; wr_data = 256'hBEEF;
    @(negedge clk);
    if (overflow) begin $display("FAIL: full+rd should not overflow"); errors++; end
    if (!wr_ready && count == 6'd4) begin
      $display("FAIL: full+rd should keep wr_ready"); errors++;
    end
    wr_valid = 0; rd_ready = 0;

    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d", errors);
    $finish;
  end

  initial begin
    #10000;
    $display("FAIL: timeout");
    $finish;
  end

endmodule
