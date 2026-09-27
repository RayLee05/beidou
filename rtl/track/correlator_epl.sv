// =============================================================================
// correlator_epl.sv -- E/P/L × I/Q 共 6 路相干累加器
//   ms_boundary 与"新 1 ms 窗口第一个样本"同拍：先转存(dump)上一窗口结果，再清零累加
//   dump_valid 比 ms_boundary 晚一拍，供环路在同一空隙内完成更新
//   累加器宽度 CORR_ACC_W=26 由最坏情况推导（scripts/fixed_point_budget.py）
//   需求: REQ-TRK-002/005, REQ-VERIF-004
// =============================================================================
`include "b1i_params.svh"

module correlator_epl (
  input  logic                                         clk,
  input  logic                                         rst_n,
  input  logic                                         sample_valid,
  input  logic                                         ms_tick,
  input  logic signed [SAMPLE_W+CARR_LUT_DATA_W-1:0]   mix_i,
  input  logic signed [SAMPLE_W+CARR_LUT_DATA_W-1:0]   mix_q,
  input  logic                                         e_tap,
  input  logic                                         p_tap,
  input  logic                                         l_tap,
  output logic signed [CORR_ACC_W-1:0]                 acc_i_e,
  output logic signed [CORR_ACC_W-1:0]                 acc_q_e,
  output logic signed [CORR_ACC_W-1:0]                 acc_i_p,
  output logic signed [CORR_ACC_W-1:0]                 acc_q_p,
  output logic signed [CORR_ACC_W-1:0]                 acc_i_l,
  output logic signed [CORR_ACC_W-1:0]                 acc_q_l,
  output logic                                         dump_valid,
  output logic signed [CORR_ACC_W-1:0]                 dump_i_e,
  output logic signed [CORR_ACC_W-1:0]                 dump_q_e,
  output logic signed [CORR_ACC_W-1:0]                 dump_i_p,
  output logic signed [CORR_ACC_W-1:0]                 dump_q_p,
  output logic signed [CORR_ACC_W-1:0]                 dump_i_l,
  output logic signed [CORR_ACC_W-1:0]                 dump_q_l
);

  logic signed [CORR_ACC_W-1:0] s_i_e, s_q_e;
  logic signed [CORR_ACC_W-1:0] s_i_p, s_q_p;
  logic signed [CORR_ACC_W-1:0] s_i_l, s_q_l;

  assign s_i_e = e_tap ? mix_i : -mix_i;
  assign s_q_e = e_tap ? mix_q : -mix_q;
  assign s_i_p = p_tap ? mix_i : -mix_i;
  assign s_q_p = p_tap ? mix_q : -mix_q;
  assign s_i_l = l_tap ? mix_i : -mix_i;
  assign s_q_l = l_tap ? mix_q : -mix_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc_i_e <= '0; acc_q_e <= '0;
      acc_i_p <= '0; acc_q_p <= '0;
      acc_i_l <= '0; acc_q_l <= '0;
      dump_i_e <= '0; dump_q_e <= '0;
      dump_i_p <= '0; dump_q_p <= '0;
      dump_i_l <= '0; dump_q_l <= '0;
      dump_valid <= 1'b0;
    end else begin
      dump_valid <= 1'b0;
      if (sample_valid) begin
        if (ms_tick) begin
          // 本窗口最后一个样本：连同本样本一起转存，然后清零。
          // ms_tick 后一拍 dump_valid=1，环路在该拍完成更新并"旁路"生效，
          // 因此新窗口的第一个样本就已经使用新系数（零滞后）。
          dump_i_e <= acc_i_e + s_i_e; dump_q_e <= acc_q_e + s_q_e;
          dump_i_p <= acc_i_p + s_i_p; dump_q_p <= acc_q_p + s_q_p;
          dump_i_l <= acc_i_l + s_i_l; dump_q_l <= acc_q_l + s_q_l;
          dump_valid <= 1'b1;
          acc_i_e <= '0; acc_q_e <= '0;
          acc_i_p <= '0; acc_q_p <= '0;
          acc_i_l <= '0; acc_q_l <= '0;
        end else begin
          dump_valid <= 1'b0;
          acc_i_e <= acc_i_e + s_i_e; acc_q_e <= acc_q_e + s_q_e;
          acc_i_p <= acc_i_p + s_i_p; acc_q_p <= acc_q_p + s_q_p;
          acc_i_l <= acc_i_l + s_i_l; acc_q_l <= acc_q_l + s_q_l;
        end
      end
    end
  end

endmodule
