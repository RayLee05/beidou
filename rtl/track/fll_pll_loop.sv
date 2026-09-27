// =============================================================================
// fll_pll_loop.sv -- 载波跟踪：Costas 相位鉴别 + 二阶 PLL + FLL 辅助
//   相位鉴别: disc = (I>=0) ? Q : -Q            （Costas，对数据位翻转不敏感）
//   FLL 辅助: 用相邻 1 ms 判别器之差作为频率误差，经 FLL_KP 注入频率积分器
//   载波频率字 freq_word = FREQ_WORD_IF + doppler，输出直接给混频 NCO
//   锁定判决: |I|+|Q|/2 高于门限时计数加一，否则减一，饱和于 [0, LOCK_COUNT_MAX]
//   需求: REQ-TRK-003/004
// =============================================================================
`include "b1i_params.svh"

module fll_pll_loop #(
  parameter int KP = PLL_KP_DEFAULT,
  parameter int KI = PLL_KI_DEFAULT,
  parameter int FLL_KP = FLL_KP_DEFAULT,
  parameter int DISC_SHIFT = DISC_SHIFT_DEFAULT
) (
  input  logic                          clk,
  input  logic                          rst_n,
  input  logic                          update,
  input  logic                          fll_en,
  input  logic                          load,
  input  logic signed [FREQ_WORD_W-1:0] init_doppler,
  input  logic signed [CORR_ACC_W-1:0]  i_p,
  input  logic signed [CORR_ACC_W-1:0]  q_p,
  input  logic signed [CORR_ACC_W-1:0]  lock_thresh,
  output logic [FREQ_WORD_W-1:0]        freq_word,
  output logic signed [15:0]            disc_dbg,
  output logic                          locked,
  output logic [7:0]                    lock_cnt
);

  localparam logic signed [LOOP_COEF_W-1:0] KP_C     = KP;
  localparam logic signed [LOOP_COEF_W-1:0] KI_C     = KI;
  localparam logic signed [LOOP_COEF_W-1:0] FLL_KP_C = FLL_KP;

  function automatic [CORR_ACC_W:0] absq(input logic signed [CORR_ACC_W-1:0] v);
    logic signed [CORR_ACC_W:0] vx;
    begin
      vx   = v;
      absq = vx[CORR_ACC_W] ? -vx : vx;
    end
  endfunction

  function automatic logic signed [15:0] sat16(input logic signed [CORR_ACC_W:0] v,
                                               input int unsigned sh);
    logic signed [CORR_ACC_W:0] s;
    begin
      s = v >>> sh;
      if (s > 32767)        sat16 = 16'sd32767;
      else if (s < -32768)  sat16 = -16'sd32768;
      else                  sat16 = s[15:0];
    end
  endfunction

  logic signed [CORR_ACC_W:0]  disc_full;
  logic signed [15:0]          disc, disc_prev;
  logic signed [31:0]          facc_q, facc_next;
  logic signed [31:0]          p_term, i_step, f_step, fll_disc;
  wire  [CORR_ACC_W:0]         mag_p;
  logic [7:0]                  lock_q;

  assign disc_full = i_p[CORR_ACC_W-1] ? (-$signed({i_p[CORR_ACC_W-1], i_p}))
                                       : $signed({1'b0, q_p});
  assign disc      = sat16(disc_full, DISC_SHIFT);

  assign fll_disc = $signed(disc) - $signed(disc_prev);
  assign p_term   = (KP_C * disc) >>> LOOP_COEF_FRAC_W;
  assign i_step   = (KI_C * disc) >>> LOOP_COEF_FRAC_W;
  assign f_step   = (FLL_KP_C * fll_disc) >>> LOOP_COEF_FRAC_W;

  assign mag_p    = absq(i_p) + (absq(q_p) >>> 1);

  localparam signed [31:0] DOP_MAX = 32'sd2621440;   // ±10 kHz

  logic signed [31:0] facc_next_clamped;
  wire  signed [31:0] facc_eff;

  assign facc_next = facc_q + i_step + (fll_en ? f_step : 32'sd0);
  assign facc_next_clamped = (facc_next > DOP_MAX)  ? DOP_MAX :
                             (facc_next < -DOP_MAX) ? -DOP_MAX : facc_next;

  // update 有效拍旁路到输出，使新窗口第一个样本即使用新的频率
  assign facc_eff = update ? facc_next_clamped : facc_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      facc_q    <= 32'sd0;
      disc_prev <= 16'sd0;
      lock_q    <= 8'd0;
    end else if (load) begin
      facc_q    <= $signed(init_doppler);
      disc_prev <= 16'sd0;
      lock_q    <= 8'd0;
    end else if (update) begin
      disc_prev <= disc;
      facc_q <= facc_next_clamped;

      if (mag_p > lock_thresh[CORR_ACC_W:0])
        lock_q <= (lock_q == 8'd255) ? lock_q : lock_q + 8'd1;
      else
        lock_q <= (lock_q == 8'd0) ? lock_q : lock_q - 8'd1;
    end
  end

  assign freq_word = FREQ_WORD_IF + facc_eff + (update ? p_term : 32'sd0);
  assign disc_dbg  = disc;
  assign locked    = (lock_q >= 8'd200);
  assign lock_cnt  = lock_q;

endmodule
