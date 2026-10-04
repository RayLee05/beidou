// =============================================================================
// correlator_epl.sv -- E/P/L × I/Q 共 6 路相干累加器
//   win_last 与"本窗口最后一个样本"同拍（跟踪通道里即码周期越界样本）：
//   该样本连同累加值一起转存，累加器清零；dump_valid 在下一拍为 1。
//   clear（装载时）清零累加器、不产生 dump。
//   累加器宽度 CORR_ACC_W=26 由最坏情况推导（scripts/fixed_point_budget.py）
//   需求: REQ-TRK-002/005, REQ-VERIF-004
// =============================================================================
`include "b1i_params.svh"

module correlator_epl (
  input  logic                                         clk,
  input  logic                                         rst_n,
  input  logic                                         clear,
  input  logic                                         sample_valid,
  input  logic                                         win_last,
  input  logic signed [SAMPLE_W+CARR_LUT_DATA_W-1:0]   mix_i,
  input  logic signed [SAMPLE_W+CARR_LUT_DATA_W-1:0]   mix_q,
  input  logic                                         e_tap,
  input  logic                                         p_tap,
  input  logic                                         l_tap,
  output logic                                         dump_valid,
  output logic signed [CORR_ACC_W-1:0]                 dump_i_e,
  output logic signed [CORR_ACC_W-1:0]                 dump_q_e,
  output logic signed [CORR_ACC_W-1:0]                 dump_i_p,
  output logic signed [CORR_ACC_W-1:0]                 dump_q_p,
  output logic signed [CORR_ACC_W-1:0]                 dump_i_l,
  output logic signed [CORR_ACC_W-1:0]                 dump_q_l
);

  logic signed [CORR_ACC_W-1:0] acc_i_e, acc_q_e, acc_i_p, acc_q_p, acc_i_l, acc_q_l;
  logic signed [CORR_ACC_W-1:0] s_i_e, s_q_e, s_i_p, s_q_p, s_i_l, s_q_l;

  // 码值约定：bit=1 -> +1，bit=0 -> -1
  assign s_i_e = e_tap ? mix_i : -mix_i;
  assign s_q_e = e_tap ? mix_q : -mix_q;
  assign s_i_p = p_tap ? mix_i : -mix_i;
  assign s_q_p = p_tap ? mix_q : -mix_q;
  assign s_i_l = l_tap ? mix_i : -mix_i;
  assign s_q_l = l_tap ? mix_q : -mix_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc_i_e <= '0; acc_q_e <= '0; acc_i_p <= '0; acc_q_p <= '0; acc_i_l <= '0; acc_q_l <= '0;
      dump_i_e <= '0; dump_q_e <= '0; dump_i_p <= '0; dump_q_p <= '0; dump_i_l <= '0; dump_q_l <= '0;
      dump_valid <= 1'b0;
    end else begin
      dump_valid <= 1'b0;
      if (clear) begin
        acc_i_e <= '0; acc_q_e <= '0; acc_i_p <= '0; acc_q_p <= '0; acc_i_l <= '0; acc_q_l <= '0;
      end else if (sample_valid) begin
        if (win_last) begin
          dump_i_e <= acc_i_e + s_i_e; dump_q_e <= acc_q_e + s_q_e;
          dump_i_p <= acc_i_p + s_i_p; dump_q_p <= acc_q_p + s_q_p;
          dump_i_l <= acc_i_l + s_i_l; dump_q_l <= acc_q_l + s_q_l;
          dump_valid <= 1'b1;
          acc_i_e <= '0; acc_q_e <= '0; acc_i_p <= '0; acc_q_p <= '0; acc_i_l <= '0; acc_q_l <= '0;
        end else begin
          acc_i_e <= acc_i_e + s_i_e; acc_q_e <= acc_q_e + s_q_e;
          acc_i_p <= acc_i_p + s_i_p; acc_q_p <= acc_q_p + s_q_p;
          acc_i_l <= acc_i_l + s_i_l; acc_q_l <= acc_q_l + s_q_l;
        end
      end
    end
  end

endmodule
