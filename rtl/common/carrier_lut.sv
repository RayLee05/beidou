// =============================================================================
// carrier_lut.sv -- 载波 sin/cos 查表（组合）
//   相位 = 32 bit 无符号；地址 = 高 CARR_LUT_ADDR_W 位（相位截断）
//   表值由 scripts/gen_carrier_lut.py 生成，与 Python 模型同源
//   需求: REQ-TRK-002 / REQ-SIG-009   预算: docs/FIXED_POINT.md 第 4 节
// =============================================================================
`include "b1i_params.svh"
`include "carrier_lut_table.svh"

module carrier_lut (
  input  logic [NCO_PHASE_W-1:0]            phase,
  output logic signed [CARR_LUT_DATA_W-1:0] cos_v,
  output logic signed [CARR_LUT_DATA_W-1:0] sin_v
);

  logic [CARR_LUT_ADDR_W-1:0] addr;

  assign addr  = phase[NCO_PHASE_W-1 -: CARR_LUT_ADDR_W];
  assign cos_v = carr_cos(addr);
  assign sin_v = carr_sin(addr);

endmodule
