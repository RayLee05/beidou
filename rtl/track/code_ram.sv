// =============================================================================
// code_ram.sv -- PRN 码 RAM（2046 x 1 bit，一写三读）
//   码表由 prn_code_gen 按 ICD 生成后经写端口装入（REQ-SIG-006）；
//   三个读口分别给 E/P/L 抽头，读地址由上级按码相位计算（异步读）。
//   注：不能用 initial 预置 mem —— VCS 会判 mem 被 always_ff 与 initial 同时驱动。
// =============================================================================
`include "b1i_params.svh"

module code_ram #(
  parameter int unsigned LEN = CODE_CHIPS_PER_PERIOD
) (
  input  logic        clk,
  input  logic        we,
  input  logic [10:0] waddr,
  input  logic        wdata,
  input  logic [10:0] e_idx,
  input  logic [10:0] p_idx,
  input  logic [10:0] l_idx,
  output logic        e_tap,
  output logic        p_tap,
  output logic        l_tap
);

  logic mem [0:LEN-1];

  always_ff @(posedge clk) begin
    if (we && waddr < LEN) mem[waddr] <= wdata;
  end

  assign e_tap = mem[e_idx];
  assign p_tap = mem[p_idx];
  assign l_tap = mem[l_idx];

endmodule
