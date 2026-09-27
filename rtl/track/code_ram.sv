// =============================================================================
// code_ram.sv -- PRN 码 RAM + E/P/L 三抽头
//   ⚠ 码表内容不由本模块产生：真值必须来自正式 B1I ICD（REQ-SIG-006）。
//     本模块只提供"可加载 + 三抽头取码"的结构；仿真中用测试图案加载，
//     图案来源见 sw/b1i_ref/codegen.py 的 TEST_PATTERN 说明。
//   抽头索引按 LEN 回绕；spacing 单位为整数码片（v1 默认 1）
// =============================================================================
`include "b1i_params.svh"

module code_ram #(
  parameter int unsigned LEN = CODE_CHIPS_PER_PERIOD
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        we,
  input  logic [10:0] waddr,
  input  logic        wdata,
  input  logic [10:0] chip_idx,
  input  logic [3:0]  spacing,
  output logic        e_tap,
  output logic        p_tap,
  output logic        l_tap,
  output logic [10:0] e_idx,
  output logic [10:0] l_idx
);

  logic mem [0:LEN-1];
  integer i;
  integer e_tmp, l_tmp;

  initial begin
    for (i = 0; i < LEN; i = i + 1) mem[i] = 1'b0;
  end

  always_ff @(posedge clk) begin
    if (we) mem[waddr % LEN] <= wdata;
  end

  always_comb begin
    e_tmp = chip_idx - spacing;
    if (e_tmp < 0) e_tmp = e_tmp + LEN;
    l_tmp = chip_idx + spacing;
    if (l_tmp >= LEN) l_tmp = l_tmp - LEN;
    e_idx = e_tmp[10:0];
    l_idx = l_tmp[10:0];
  end

  assign p_tap = mem[chip_idx];
  assign e_tap = mem[e_idx];
  assign l_tap = mem[l_idx];

endmodule
