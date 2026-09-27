// =============================================================================
// dll_loop.sv -- 码环（DLL）鉴别器 + 二阶环路滤波
//   鉴别器: disc = (|Ie|+|Qe|/2) - (|Il|+|Ql|/2)      （非归一化 EML，见文档说明）
//   压位: DISC_SHIFT 把 26 bit 相关值压到 16 bit 判别器后再做乘法（省面积）
//   环路: code_inc = CODE_INC_NOMINAL + (Kp*disc)>>14 + 积分项
//   输出限幅在 [CODE_INC_MIN, CODE_INC_MAX]，防码环跑飞
//   需求: REQ-TRK-003/004
// =============================================================================
`include "b1i_params.svh"

module dll_loop #(
  parameter int KP = DLL_KP_DEFAULT,
  parameter int KI = DLL_KI_DEFAULT,
  parameter int DISC_SHIFT = DISC_SHIFT_DEFAULT
) (
  input  logic                          clk,
  input  logic                          rst_n,
  input  logic                          update,
  input  logic signed [CORR_ACC_W-1:0]  i_e,
  input  logic signed [CORR_ACC_W-1:0]  q_e,
  input  logic signed [CORR_ACC_W-1:0]  i_l,
  input  logic signed [CORR_ACC_W-1:0]  q_l,
  output logic signed [CODE_PHASE_W-1:0] code_inc,
  output logic signed [15:0]            disc_dbg,
  output logic signed [31:0]            integ_dbg
);

  localparam logic signed [LOOP_COEF_W-1:0] KP_C = KP;
  localparam logic signed [LOOP_COEF_W-1:0] KI_C = KI;

  function automatic [CORR_ACC_W:0] absq(input logic signed [CORR_ACC_W-1:0] v);
    logic signed [CORR_ACC_W:0] vx;
    begin
      vx   = v;
      absq = vx[CORR_ACC_W] ? -vx : vx;
    end
  endfunction

  function automatic logic signed [15:0] sat16(input logic signed [CORR_ACC_W+1:0] v,
                                               input int unsigned sh);
    logic signed [CORR_ACC_W+1:0] s;
    begin
      s = v >>> sh;
      if (s > 32767)        sat16 = 16'sd32767;
      else if (s < -32768)  sat16 = -16'sd32768;
      else                  sat16 = s[15:0];
    end
  endfunction

  wire [CORR_ACC_W:0]           mag_e = absq(i_e) + (absq(q_e) >>> 1);
  wire [CORR_ACC_W:0]           mag_l = absq(i_l) + (absq(q_l) >>> 1);
  wire signed [CORR_ACC_W+1:0]  disc_full;
  wire signed [15:0]            disc;
  wire signed [31:0]            p_term;
  wire signed [31:0]            i_step;
  wire signed [31:0]            integ_next;
  wire signed [31:0]            inc_full;

  assign disc_full = $signed({1'b0, mag_e}) - $signed({1'b0, mag_l});
  assign disc      = sat16(disc_full, DISC_SHIFT);

  assign p_term = (KP_C * disc) >>> LOOP_COEF_FRAC_W;
  assign i_step = (KI_C * disc) >>> LOOP_COEF_FRAC_W;

  // 积分项限幅：±(CODE_INC_MAX - CODE_INC_NOMINAL)
  logic signed [31:0] integ_q;
  logic signed [31:0] integ_next_clamped;
  wire  signed [31:0] integ_eff;

  assign integ_next = integ_q + i_step;
  assign integ_next_clamped = (integ_next > 32'sd3840)  ? 32'sd3840 :
                              (integ_next < -32'sd3840) ? -32'sd3840 : integ_next;

  // update 有效拍直接旁路到输出：新窗口的第一个样本就使用新的码率
  assign integ_eff = update ? integ_next_clamped : integ_q;
  // 负反馈：本地码超前(e>0) => magE>magL => disc>0 => 降低码率把它拉回来
  assign inc_full  = $signed({1'b0, CODE_INC_NOMINAL[30:0]})
                     - (update ? p_term : 32'sd0) - integ_eff;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      integ_q <= 32'sd0;
    end else if (update) begin
      if (integ_next > 32'sd3840)       integ_q <= 32'sd3840;
      else if (integ_next < -32'sd3840) integ_q <= -32'sd3840;
      else                              integ_q <= integ_next;
    end
  end

  assign disc_dbg   = disc;
  assign integ_dbg  = integ_q;
  assign code_inc   = inc_full;

endmodule
