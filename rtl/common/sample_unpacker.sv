// =============================================================================
// sample_unpacker.sv -- 1 字节 -> 4 个 2 bit 有符号样本
//   打包顺序: [7:6] 最早，依次 [5:4] / [3:2] / [1:0]（早样本在高位）
//   映射: 00 -> -3, 01 -> -1, 10 -> +1, 11 -> +3
//   每字节消耗 4 个时钟，byte_ready 低时上级必须保持数据
//   需求: REQ-SIG-004/005, REQ-IN-003
// =============================================================================
`include "b1i_params.svh"

module sample_unpacker (
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic                       byte_valid,
  input  logic [7:0]                 data_byte,
  output logic                       byte_ready,
  output logic                       sample_valid,
  output logic signed [SAMPLE_W-1:0] sample
);

  logic [7:0] sr;
  logic [2:0] cnt;
  logic       busy;

  assign byte_ready   = ~busy;
  assign sample_valid = busy;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sr   <= 8'h00;
      cnt  <= 3'd0;
      busy <= 1'b0;
    end else if (!busy) begin
      if (byte_valid) begin
        sr   <= data_byte;
        cnt  <= 3'd0;
        busy <= 1'b1;
      end
    end else begin
      sr <= {sr[5:0], 2'b00};
      if (cnt == 3'd3) busy <= 1'b0;
      cnt <= cnt + 3'd1;
    end
  end

  always_comb begin
    case (sr[7:6])
      2'b00:   sample = -3;
      2'b01:   sample = -1;
      2'b10:   sample =  1;
      default: sample =  3;
    endcase
  end

endmodule
