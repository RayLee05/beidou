// =============================================================================
// track_loop.sv -- 跟踪环路：归一化鉴别器 + PLL/FLL + DLL + 锁定检测
//   每个完整窗口的 dump 触发一次更新，单个 28x17 乘法器按步骤复用（S1..S12）。
//   结果寄存后组合给出 pend_freq_word / pend_code_inc，由通道在下一个码周期边界生效。
//   逐位参考：sw/b1i_ref/tracking_model.py 的 LoopState.update()
//
//   幅度估计   amp = have ? amp + ((magP-amp)>>>3) : magP，magX = |I|+(|Q|>>1)
//   归一化     norm(x) = (x * RECIP[m]) >>> (L+3)，L = amp 最高位位置，m = 其后 5 位
//   PLL 鉴别   d_pll = sign(Ipn)*Qpn                    （Costas，≈ 4096·sinφ）
//   FLL 鉴别   d_fll = sign(dot)*xprod >>> 12            （≈ 4096·sin(2π·Δf·T)）
//   DLL 鉴别   d_dll = norm(magE - magL)                 （±0.5 chip 时 ≈ 8192·τ）
//   载波       facc += (Ki*d_pll + Kf*d_fll)>>>14；freq = IF + facc + (Kp*d_pll)>>>14
//   码         dacc += (Ki*d_dll)>>>8；inc = NOM + (facc*2749)>>>16 + (Kp*d_dll)>>>8 + dacc
//   锁定       每 LOCK_BLOCK 次更新比较 Σ|Ip| > 2Σ|Qp|，计数达 LOCK_ON 置锁定、回到 0 失锁
//   需求: REQ-TRK-003/004/006
// =============================================================================
`include "b1i_params.svh"

module track_loop (
  input  logic                          clk,
  input  logic                          rst_n,
  input  logic                          load,
  input  logic signed [FREQ_WORD_W-1:0] init_dop,
  input  logic                          fll_en,
  input  logic signed [15:0]            pll_kp,
  input  logic signed [15:0]            pll_ki,
  input  logic signed [15:0]            fll_k,
  input  logic signed [15:0]            dll_kp,
  input  logic signed [15:0]            dll_ki,
  input  logic                          start,       // dump_valid 且非不完整窗口
  input  logic signed [CORR_ACC_W-1:0]  i_e, q_e, i_p, q_p, i_l, q_l,
  output logic [FREQ_WORD_W-1:0]        pend_freq_word,
  output logic [CODE_NCO_W-1:0]         pend_code_inc,
  output logic signed [FREQ_WORD_W-1:0] dop_word,
  output logic                          busy,
  output logic                          locked,
  output logic [3:0]                    lock_cnt,
  output logic [27:0]                   amp_dbg,
  output logic signed [15:0]            d_pll_dbg,
  output logic signed [15:0]            d_fll_dbg,
  output logic signed [15:0]            d_dll_dbg
);

  // ---------------------------------------------------------------- 常量
  localparam logic signed [33:0] DOP_MAX = $signed({2'b00, FREQ_WORD_DOP_MAX});
  localparam logic signed [33:0] DACC_MAX = 34'sd131072;

  function automatic logic [15:0] recip_lut(input logic [4:0] m);
    case (m)
      5'd0:  recip_lut = 16'd32264;  5'd1:  recip_lut = 16'd31301;
      5'd2:  recip_lut = 16'd30394;  5'd3:  recip_lut = 16'd29537;
      5'd4:  recip_lut = 16'd28728;  5'd5:  recip_lut = 16'd27962;
      5'd6:  recip_lut = 16'd27236;  5'd7:  recip_lut = 16'd26546;
      5'd8:  recip_lut = 16'd25891;  5'd9:  recip_lut = 16'd25267;
      5'd10: recip_lut = 16'd24672;  5'd11: recip_lut = 16'd24105;
      5'd12: recip_lut = 16'd23564;  5'd13: recip_lut = 16'd23046;
      5'd14: recip_lut = 16'd22550;  5'd15: recip_lut = 16'd22075;
      5'd16: recip_lut = 16'd21620;  5'd17: recip_lut = 16'd21183;
      5'd18: recip_lut = 16'd20764;  5'd19: recip_lut = 16'd20361;
      5'd20: recip_lut = 16'd19973;  5'd21: recip_lut = 16'd19600;
      5'd22: recip_lut = 16'd19240;  5'd23: recip_lut = 16'd18893;
      5'd24: recip_lut = 16'd18559;  5'd25: recip_lut = 16'd18236;
      5'd26: recip_lut = 16'd17924;  5'd27: recip_lut = 16'd17623;
      5'd28: recip_lut = 16'd17332;  5'd29: recip_lut = 16'd17050;
      5'd30: recip_lut = 16'd16777;  default: recip_lut = 16'd16513;
    endcase
  endfunction

  function automatic logic signed [15:0] sat16(input logic signed [47:0] v);
    if (v > 48'sd32767)       sat16 = 16'sd32767;
    else if (v < -48'sd32768) sat16 = -16'sd32768;
    else                      sat16 = v[15:0];
  endfunction

  function automatic logic signed [33:0] clamp34(input logic signed [33:0] v,
                                                 input logic signed [33:0] lim);
    if (v > lim)       clamp34 = lim;
    else if (v < -lim) clamp34 = -lim;
    else               clamp34 = v;
  endfunction

  function automatic logic [26:0] mag(input logic signed [CORR_ACC_W-1:0] i,
                                      input logic signed [CORR_ACC_W-1:0] q);
    logic [26:0] ai, aq;
    ai  = i[CORR_ACC_W-1] ? 27'(-{i[CORR_ACC_W-1], i}) : 27'(i);
    aq  = q[CORR_ACC_W-1] ? 27'(-{q[CORR_ACC_W-1], q}) : 27'(q);
    mag = ai + (aq >> 1);
  endfunction

  function automatic logic [26:0] abs26(input logic signed [CORR_ACC_W-1:0] v);
    abs26 = v[CORR_ACC_W-1] ? 27'(-{v[CORR_ACC_W-1], v}) : 27'(v);
  endfunction

  // ---------------------------------------------------------------- 状态
  logic [3:0]          step;
  logic signed [27:0]  amp;
  logic                have_amp, have_prev;
  logic signed [15:0]  ipn, qpn, ipn_prev, qpn_prev;
  logic signed [15:0]  d_pll, d_fll, d_dll;
  logic signed [32:0]  t1, xprod;
  logic signed [31:0]  facc, dacc, p_pll, i_pll, f_fll, p_dll;
  logic [31:0]         blk_i, blk_q;
  logic [4:0]          blk_n;
  logic [3:0]          lcnt;
  logic                locked_q;

  // ---------------------------------------------------------------- 组合
  wire [26:0] mag_p = mag(i_p, q_p);
  wire [26:0] mag_e = mag(i_e, q_e);
  wire [26:0] mag_l = mag(i_l, q_l);

  wire signed [28:0] amp_diff  = $signed({2'b00, mag_p}) - $signed({amp[27], amp});
  wire signed [27:0] amp_next  = have_amp ? 28'(amp + (amp_diff >>> AMP_SHIFT))
                                          : $signed({1'b0, mag_p});

  logic [27:0] amp_eff;
  logic [4:0]  msb;
  logic [4:0]  mant;
  always_comb begin
    amp_eff = (amp < $signed(28'(AMP_MIN))) ? 28'(AMP_MIN) : amp;
    msb = 5'd0;
    for (int b = 0; b < 28; b++) if (amp_eff[b]) msb = 5'(b);
    mant = 5'(amp_eff >> (msb - 5'd5));
  end
  wire [5:0]  norm_sh = 6'(msb) + 6'(15 - NORM_W);
  wire [15:0] recip   = recip_lut(mant);

  // 共享乘法器
  logic signed [27:0] mul_a;
  logic signed [16:0] mul_b;
  wire  signed [44:0] prod = mul_a * mul_b;
  wire  signed [44:0] prod_norm = prod >>> norm_sh;

  wire signed [27:0] dll_err = $signed({1'b0, mag_e}) - $signed({1'b0, mag_l});

  always_comb begin
    mul_a = '0;
    mul_b = '0;
    case (step)
      4'd1:  begin mul_a = 28'(i_p);     mul_b = $signed({1'b0, recip}); end
      4'd2:  begin mul_a = 28'(q_p);     mul_b = $signed({1'b0, recip}); end
      4'd3:  begin mul_a = dll_err;      mul_b = $signed({1'b0, recip}); end
      4'd4:  begin mul_a = 28'(ipn_prev); mul_b = 17'(qpn);    end
      4'd5:  begin mul_a = 28'(ipn);      mul_b = 17'(qpn_prev); end
      4'd6:  begin mul_a = 28'(ipn_prev); mul_b = 17'(ipn);    end
      4'd7:  begin mul_a = 28'(qpn_prev); mul_b = 17'(qpn);    end
      4'd8:  begin mul_a = 28'(d_pll);    mul_b = 17'(pll_kp); end
      4'd9:  begin mul_a = 28'(d_pll);    mul_b = 17'(pll_ki); end
      4'd10: begin mul_a = 28'(d_fll);    mul_b = 17'(fll_k);  end
      4'd11: begin mul_a = 28'(d_dll);    mul_b = 17'(dll_kp); end
      4'd12: begin mul_a = 28'(d_dll);    mul_b = 17'(dll_ki); end
      default: ;
    endcase
  end

  wire signed [32:0] dot    = t1 + 33'(prod);
  wire signed [32:0] cr_sel = (dot >= 0) ? xprod : -xprod;
  wire signed [33:0] facc_sum = 34'(facc) + 34'(i_pll) + (fll_en ? 34'(f_fll) : 34'sd0);
  wire signed [33:0] dacc_sum = 34'(dacc) + 34'(prod >>> 8);
  wire               blk_last = (blk_n == 5'(LOCK_BLOCK - 1));
  wire [31:0]        blk_i_n  = blk_i + 32'(abs26(i_p));
  wire [31:0]        blk_q_n  = blk_q + 32'(abs26(q_p));

  // ---------------------------------------------------------------- 时序
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      step <= 4'd0;
      amp <= '0; have_amp <= 1'b0; have_prev <= 1'b0;
      ipn <= '0; qpn <= '0; ipn_prev <= '0; qpn_prev <= '0;
      d_pll <= '0; d_fll <= '0; d_dll <= '0; t1 <= '0; xprod <= '0;
      facc <= '0; dacc <= '0; p_pll <= '0; i_pll <= '0; f_fll <= '0; p_dll <= '0;
      blk_i <= '0; blk_q <= '0; blk_n <= '0; lcnt <= '0; locked_q <= 1'b0;
    end else if (load) begin
      step <= 4'd0;
      amp <= '0; have_amp <= 1'b0; have_prev <= 1'b0;
      ipn_prev <= '0; qpn_prev <= '0;
      facc <= 32'(clamp34(34'(init_dop), DOP_MAX));
      dacc <= '0; p_pll <= '0; p_dll <= '0;
      blk_i <= '0; blk_q <= '0; blk_n <= '0; lcnt <= '0; locked_q <= 1'b0;
    end else begin
      case (step)
        4'd0: if (start) begin
          amp <= amp_next;
          have_amp <= 1'b1;
          step <= 4'd1;
        end
        4'd1: begin ipn <= sat16(48'(prod_norm)); step <= 4'd2; end
        4'd2: begin qpn <= sat16(48'(prod_norm)); step <= 4'd3; end
        4'd3: begin
          d_dll <= sat16(48'(prod_norm));
          d_pll <= (ipn >= 0) ? qpn : sat16(-48'(qpn));
          step <= 4'd4;
        end
        4'd4: begin t1 <= 33'(prod); step <= 4'd5; end
        4'd5: begin xprod <= t1 - 33'(prod); step <= 4'd6; end
        4'd6: begin t1 <= 33'(prod); step <= 4'd7; end
        4'd7: begin
          d_fll <= have_prev ? sat16(48'(cr_sel >>> 12)) : 16'sd0;
          ipn_prev <= ipn; qpn_prev <= qpn; have_prev <= 1'b1;
          step <= 4'd8;
        end
        4'd8:  begin p_pll <= 32'(prod >>> 14); step <= 4'd9;  end
        4'd9:  begin i_pll <= 32'(prod >>> 14); step <= 4'd10; end
        4'd10: begin f_fll <= 32'(prod >>> 14); step <= 4'd11; end
        4'd11: begin p_dll <= 32'(prod >>> 8);  step <= 4'd12; end
        4'd12: begin
          dacc <= 32'(clamp34(dacc_sum, DACC_MAX));
          facc <= 32'(clamp34(facc_sum, DOP_MAX));
          if (blk_last) begin
            if (blk_i_n > (blk_q_n << 1)) lcnt <= (lcnt == 4'(LOCK_MAX)) ? lcnt : lcnt + 4'd1;
            else                          lcnt <= (lcnt == 4'd0) ? lcnt : lcnt - 4'd1;
            blk_i <= '0; blk_q <= '0; blk_n <= '0;
          end else begin
            blk_i <= blk_i_n; blk_q <= blk_q_n; blk_n <= blk_n + 5'd1;
          end
          step <= 4'd13;
        end
        default: begin   // 4'd13：锁定状态随新计数更新
          if (lcnt >= 4'(LOCK_ON)) locked_q <= 1'b1;
          else if (lcnt == 4'd0)   locked_q <= 1'b0;
          step <= 4'd0;
        end
      endcase
    end
  end

  // ---------------------------------------------------------------- 输出
  wire signed [44:0] aid = (45'(facc) * 45'sd2749) >>> CODE_AID_SHIFT;

  assign pend_freq_word = FREQ_WORD_IF + facc + p_pll;
  assign pend_code_inc  = CODE_NCO_INC_NOMINAL + 48'(aid) + 48'(p_dll) + 48'(dacc);
  assign dop_word       = facc;
  assign busy           = (step != 4'd0);
  assign locked         = locked_q;
  assign lock_cnt       = lcnt;
  assign amp_dbg        = amp;
  assign d_pll_dbg      = d_pll;
  assign d_fll_dbg      = d_fll;
  assign d_dll_dbg      = d_dll;

endmodule
