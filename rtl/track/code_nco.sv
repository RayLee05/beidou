// =============================================================================
// code_nco.sv -- PRN 码相位 NCO（Q(11.21)：整数码片[31:21] + 小数码片[20:0]）
//   一个码周期 = 2046 << 21 = CODE_PERIOD_WORD；越界即回绕并产生 epoch 脉冲
//   标称增量 261888 = round(2046/16384 * 2^21)，精确无截断误差
//   需求: REQ-TRK-002/003   预算: docs/FIXED_POINT.md 第 4/6 节
// =============================================================================
`include "b1i_params.svh"

module code_nco (
  input  logic                          clk,
  input  logic                          rst_n,
  input  logic                          sample_valid,
  input  logic signed [CODE_PHASE_W-1:0] code_inc,
  input  logic                          load,
  input  logic [CODE_PHASE_W-1:0]       phase_init,
  output logic [CODE_PHASE_W-1:0]       code_phase,
  output logic [10:0]                   chip_idx,
  output logic                          code_epoch_tick
);

  logic signed [CODE_PHASE_W:0] sum;          // 33 bit 有符号，防越界
  logic [CODE_PHASE_W-1:0]      phase_next;
  logic                         epoch_c;

  always_comb begin
    sum = $signed({1'b0, code_phase}) + $signed(code_inc);
    if (sum >= $signed({1'b0, CODE_PERIOD_WORD})) begin
      sum       = sum - $signed({1'b0, CODE_PERIOD_WORD});
      epoch_c   = 1'b1;
    end else if (sum < 0) begin
      sum       = sum + $signed({1'b0, CODE_PERIOD_WORD});
      epoch_c   = 1'b1;
    end else begin
      epoch_c   = 1'b0;
    end
    phase_next = sum[CODE_PHASE_W-1:0];
  end

  // 当前样本使用的码相位 = 更新后的相位
  assign chip_idx         = phase_next[CODE_PHASE_W-1 -: 11];
  assign code_epoch_tick  = epoch_c;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      code_phase <= '0;
    end else if (sample_valid) begin
      code_phase <= load ? phase_init : phase_next;
    end
  end

endmodule
