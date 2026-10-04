// =============================================================================
// record_fifo.sv -- 256 bit 记录同步 FIFO（valid/ready）
//   写入时 wr_valid && wr_ready 才入队；读出时 rd_valid && rd_ready 才出队。
//   满时 wr_ready=0，再写则 overflow 置 1（单拍）。DEPTH 必须为 2 的幂。
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

  localparam int AW = $clog2(DEPTH);

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
      // 满且本拍不能借读出腾位才算溢出；调度器多挂一拍 wr_valid 不算
      overflow <= wr_valid && (cnt == 6'(DEPTH)) && !do_rd;
      if (do_wr) begin
        mem[wp] <= wr_data;
        wp      <= wp + 1'b1;
      end
      if (do_rd) rp <= rp + 1'b1;
      cnt <= cnt + (do_wr ? 6'd1 : 6'd0) - (do_rd ? 6'd1 : 6'd0);
    end
  end

endmodule
