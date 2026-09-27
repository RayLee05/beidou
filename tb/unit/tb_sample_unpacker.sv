// tb_sample_unpacker.sv -- 2 bit 解包单元测试（定向）
`include "b1i_params.svh"

module tb_sample_unpacker;

  logic                       clk = 1'b0, rst_n;
  logic                       byte_valid;
  logic [7:0]                 data_byte;
  logic                       byte_ready, sample_valid;
  logic signed [SAMPLE_W-1:0] sample;
  integer errors;
  integer n;
  integer got [0:7];

  sample_unpacker dut (
    .clk(clk), .rst_n(rst_n), .byte_valid(byte_valid), .data_byte(data_byte),
    .byte_ready(byte_ready), .sample_valid(sample_valid), .sample(sample));

  always #5 clk = ~clk;

  task automatic send_byte(input [7:0] b);
    begin
      while (!byte_ready) @(negedge clk);
      @(negedge clk);
      byte_valid = 1'b1;
      data_byte  = b;
      @(negedge clk);
      byte_valid = 1'b0;
      // 采集 4 个样本
      n = 0;
      while (n < 4) begin
        @(negedge clk);
        if (sample_valid) begin
          got[n] = sample;
          n = n + 1;
        end
      end
      if (!byte_ready) begin
        $display("FAIL: 收完 4 个样本后 byte_ready 应为 1");
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    errors = 0;
    rst_n = 1'b0; byte_valid = 1'b0; data_byte = 8'h00;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    // 0x1B = 00 01 10 11 -> -3 -1 +1 +3
    send_byte(8'h1B);
    if (got[0] !== -3 || got[1] !== -1 || got[2] !== 1 || got[3] !== 3) begin
      $display("FAIL 0x1B: %0d %0d %0d %0d", got[0], got[1], got[2], got[3]);
      errors = errors + 1;
    end
    // 0xE4 = 11 10 01 00 -> +3 +1 -1 -3
    send_byte(8'hE4);
    if (got[0] !== 3 || got[1] !== 1 || got[2] !== -1 || got[3] !== -3) begin
      $display("FAIL 0xE4: %0d %0d %0d %0d", got[0], got[1], got[2], got[3]);
      errors = errors + 1;
    end

    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d", errors);
    $finish;
  end

  // 保护：任何握手卡死都应结束仿真并报错，而不是无限等待
  initial begin
    #100000;
    $display("FAIL: 仿真超时（byte_ready/sample_valid 握手未完成）");
    $finish;
  end

endmodule
