// =============================================================================
// code_nco.sv -- PRN 码相位 NCO（内部 Q(11.37) 48 bit，对外 code_phase 为 Q(11.21)）
//   每个有效样本：phase <= phase + code_inc；越过 2046 chip 即回绕，并在该样本
//   同拍给出 code_epoch（组合）。越界样本的相位已属于新码周期（码片 0）。
//   load 与样本无关，优先级高于 sample_valid（装载拍不推进相位）。
//   需求: REQ-TRK-002/003   预算: docs/FIXED_POINT.md 第 6 节
// =============================================================================
`include "b1i_params.svh"

module code_nco (
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    sample_valid,
  input  logic [CODE_NCO_W-1:0]   code_inc,
  input  logic                    load,
  input  logic [CODE_NCO_W-1:0]   phase_init,
  output logic [CODE_NCO_W-1:0]   phase,        // 已处理样本的相位（寄存）
  output logic [CODE_NCO_W-1:0]   phase_next,   // 当前样本使用的相位（组合）
  output logic                    code_epoch    // 当前样本越过码周期（组合，未门控 sample_valid）
);

  logic [CODE_NCO_W:0] sum;

  always_comb begin
    sum = {1'b0, phase} + {1'b0, code_inc};
    if (sum >= {1'b0, CODE_NCO_PERIOD}) begin
      phase_next = sum[CODE_NCO_W-1:0] - CODE_NCO_PERIOD;
      code_epoch = 1'b1;
    end else begin
      phase_next = sum[CODE_NCO_W-1:0];
      code_epoch = 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)            phase <= '0;
    else if (load)         phase <= phase_init;
    else if (sample_valid) phase <= phase_next;
  end

endmodule
