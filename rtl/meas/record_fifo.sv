// =============================================================================
// record_fifo.sv -- 256 bit 记录同步 FIFO（valid/ready）
//   写入时 wr_valid && wr_ready 才入队；读出时 rd_valid && rd_ready 才出队。
//   满时 wr_ready=0；上游保持 valid/data 属于正常背压，不报溢出。
//   overflow 保留接口兼容，合法握手不会溢出；丢弃事件由上游队列检测。
//   DEPTH 必须为 1..32 内的 2 的幂（count 接口为 6 bit）。
//   需求: REQ-MEAS-003, REQ-IO-002
// =============================================================================
`include "b1i_params.svh"

module record_fifo #(
  parameter int DEPTH = 16
) (
  input  logic         clk,
  input  logic         rst_n,
  input  logic         wr_valid,
  output logic         wr_ready,
  input  logic [255:0] wr_data,
  output logic         rd_valid,
  input  logic         rd_ready,
  output logic [255:0] rd_data,
  output logic         overflow,
  output logic [5:0]   count
);

  localparam int AW = (DEPTH > 1) ? $clog2(DEPTH) : 1;

`ifndef SYNTHESIS
  initial begin
    if (DEPTH < 1 || DEPTH > 32 || (DEPTH & (DEPTH - 1)) != 0)
      $fatal(1, "record_fifo DEPTH must be a power of two in 1..32");
  end
`endif

  logic [255:0] mem [0:DEPTH-1];
  logic [AW-1:0] wp, rp;
  logic [5:0]    cnt;

  wire do_rd = (cnt != 6'd0) && rd_ready;
  assign count    = cnt;
  assign wr_ready = (cnt != 6'(DEPTH)) || do_rd;
  assign rd_valid = (cnt != 6'd0);
  assign rd_data  = mem[rp];

  wire do_wr = wr_valid && wr_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wp <= '0; rp <= '0; cnt <= '0; overflow <= 1'b0;
    end else begin
      overflow <= 1'b0;
      if (do_wr) begin
        mem[wp] <= wr_data;
        wp      <= (wp == AW'(DEPTH - 1)) ? '0 : wp + 1'b1;
      end
      if (do_rd) rp <= (rp == AW'(DEPTH - 1)) ? '0 : rp + 1'b1;
      cnt <= cnt + (do_wr ? 6'd1 : 6'd0) - (do_rd ? 6'd1 : 6'd0);
    end
  end

endmodule
