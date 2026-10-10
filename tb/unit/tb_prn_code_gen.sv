// tb_prn_code_gen.sv -- PRN 码发生器逐码片比对（参考: sw/b1i_ref/prn_b1i.py）
`include "b1i_params.svh"

module tb_prn_code_gen;

  localparam int N_PRN = 63;

  logic clk = 1'b0, rst_n;
  always #5 clk = ~clk;

  logic [2045:0] ref_mem [0:N_PRN-1];
  logic        start, busy, done, bad_prn, out_we, out_chip;
  logic [5:0]  prn;
  logic [10:0] out_addr;
  integer      errors = 0, writes, k;

  prn_code_gen dut (
    .clk(clk), .rst_n(rst_n), .start(start), .prn(prn), .busy(busy), .done(done),
    .bad_prn(bad_prn), .out_we(out_we), .out_addr(out_addr), .out_chip(out_chip));

  always @(posedge clk) begin
    if (out_we) begin
      if (out_chip !== ref_mem[k][2045 - out_addr]) begin
        if (errors < 10) $display("MISMATCH PRN %0d chip %0d: rtl=%0d ref=%0d",
                                  k + 1, out_addr, out_chip, ref_mem[k][2045 - out_addr]);
        errors++;
      end
      writes++;
    end
  end

  initial begin
    $readmemh("tb/vectors/prn_codes.hex", ref_mem);
    rst_n = 1'b0; start = 1'b0; prn = '0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    for (k = 0; k < N_PRN; k++) begin
      writes = 0;
      @(negedge clk);
      prn = 6'(k + 1); start = 1'b1;
      @(negedge clk);
      start = 1'b0;
      wait (done);
      @(negedge clk);
      if (writes != 2046) begin
        $display("ERROR PRN %0d: %0d writes", k + 1, writes);
        errors++;
      end
    end
    // 非法 PRN
    @(negedge clk);
    prn = 6'd0; start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    @(negedge clk);
    if (!bad_prn || busy) begin
      $display("ERROR: PRN 0 should be rejected");
      errors++;
    end
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d", errors);
    $finish;
  end

endmodule
