// =============================================================================
// acquisition.sv -- 捕获引擎：回放缓冲 + N 路并行码相位相关 + 多普勒扫描 + 移交 NCO
//
//   1) CAPTURE  从实时样本流截取 BUF_DEPTH 个样本存入回放缓冲（2 bit/样本，同步读 RAM）；
//               同时开始计数截取起点之后的实时样本数 Δ。
//   2) COARSE   对 n_bins 个多普勒格、每格 PASSES 轮回放；每轮 N_LANES 路并行，
//               第 j 路本地码比第 0 路晚 j 个半码片（延迟线抽头 4j 样本），
//               覆盖半码片假设 h = h0-j。先跳过 WARM 个样本填满延迟线，
//               再做 nc 个 1 ms 相干积分、按 |I|+|Q|/2 非相干累加。
//   3) 判决     峰值所在多普勒格的平均值 mean = Σ/4096；peak*16 > mean*thr 判为捕获。
//   4) FINE     在最佳假设附近做 5 个细多普勒格（步长 dop_step/4），刷新 (h, 多普勒)。
//   5) HANDOVER 外推到当前：φ = h·2^36 + (Δ mod 16368)·2^34 + Δ·aid（模码周期），
//               再由追赶式 NCO 跟上实时流；ready=1 时 ho_phase 即"最后一个已处理样本"
//               处的码相位，可直接装入 tracking_channel。
//
//   假设与样本的约定：窗口第 k 个样本处理后，第 j 路假设的信号码相位
//     = h·2^36 + (k+1)·inc，inc = 2^34 + aid(多普勒)，h = h0 - j（半码片）。
//   需求: REQ-ACQ-001..006
// =============================================================================
`include "b1i_params.svh"

module acquisition #(
  parameter int N_LANES   = 64,                 // 2 的幂，且整除 4096
  parameter int BUF_DEPTH = 33024               // >= 4*(N_LANES-1) + nc*16368
) (
  input  logic                          clk,
  input  logic                          rst_n,
  // 实时样本流
  input  logic                          sample_valid,
  input  logic signed [SAMPLE_W-1:0]    sample,
  // 码 RAM 写口（prn_code_gen）
  input  logic                          code_we,
  input  logic [10:0]                   code_waddr,
  input  logic                          code_wdata,
  // 控制与配置
  input  logic                          start,
  input  logic                          abort,
  input  logic                          ack,          // 移交完成后由通道管理器给出
  input  logic signed [FREQ_WORD_W-1:0] dop_min,
  input  logic signed [FREQ_WORD_W-1:0] dop_step,
  input  logic [7:0]                    n_bins,
  input  logic [1:0]                    nc,           // 非相干次数 1 或 2
  input  logic [7:0]                    thr,          // Q4.4 峰均比门限
  // 状态与结果
  output logic                          busy,
  output logic                          done,         // 单拍：搜索结束（found 有效）
  output logic                          found,
  output logic                          ready,        // 移交 NCO 已跟上实时流
  output logic [CODE_NCO_W-1:0]         ho_phase,
  output logic signed [FREQ_WORD_W-1:0] res_dop,
  output logic [11:0]                   res_h,
  output logic [27:0]                   res_peak,
  output logic [27:0]                   res_mean
);

  localparam int WARM   = 4 * (N_LANES - 1);
  localparam int PASSES = 4096 / N_LANES;
  localparam int LW     = $clog2(N_LANES);
  localparam int BW     = $clog2(BUF_DEPTH);
  localparam int SPM    = SAMPLES_PER_MS;
  localparam logic [47:0] HALF_CHIP = 48'd1 << (CODE_NCO_FRAC_W - 1);

  typedef enum logic [3:0] {
    S_IDLE, S_CAPTURE, S_PASS_LOAD, S_PASS_RUN, S_SCAN, S_NEXT, S_DECIDE,
    S_PROP_MUL, S_PROP_RED, S_CATCHUP, S_READY, S_DONE
  } state_t;
  state_t st;

  // ---------------------------------------------------------------- 回放缓冲
  logic [1:0]    buf_mem [0:BUF_DEPTH-1];
  logic [BW-1:0] wr_ptr, rd_addr;
  logic [1:0]    rd_q;
  logic          rd_en;

  function automatic logic [1:0] enc2(input logic signed [SAMPLE_W-1:0] s);
    case (s)
      -3:      enc2 = 2'b00;
      -1:      enc2 = 2'b01;
      1:       enc2 = 2'b10;
      default: enc2 = 2'b11;
    endcase
  endfunction

  function automatic logic signed [SAMPLE_W-1:0] dec2(input logic [1:0] c);
    case (c)
      2'b00:   dec2 = -3;
      2'b01:   dec2 = -1;
      2'b10:   dec2 = 1;
      default: dec2 = 3;
    endcase
  endfunction

  always_ff @(posedge clk) begin
    if (st == S_CAPTURE && sample_valid) buf_mem[wr_ptr] <= enc2(sample);
    if (rd_en) rd_q <= buf_mem[rd_addr];
  end

  // ---------------------------------------------------------------- Δ 计数（截取起点后的实时样本数）
  logic [31:0] delta;
  logic [13:0] delta_mod;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      delta <= '0; delta_mod <= '0;
    end else if (st == S_IDLE && start) begin
      delta <= '0; delta_mod <= '0;
    end else if (sample_valid && st != S_IDLE) begin
      delta     <= delta + 32'd1;
      delta_mod <= (delta_mod == 14'(SPM - 1)) ? 14'd0 : delta_mod + 14'd1;
    end
  end

  // ---------------------------------------------------------------- 回放数据通路
  logic                                       pv;          // 回放样本有效（读数据拍）
  logic [BW-1:0]                              k, kd;
  logic                                       nco_load;
  logic [CODE_NCO_W-1:0]                      cp_init, cp_q, cp_next, inc;
  logic                                       epoch_unused;
  logic [FREQ_WORD_W-1:0]                     fw;
  logic [NCO_PHASE_W-1:0]                     carr_unused;
  logic signed [SAMPLE_W+CARR_LUT_DATA_W-1:0] mix_i, mix_q;
  logic                                       chip, e_unused, l_unused;
  logic signed [FREQ_WORD_W-1:0]              cur_dop;

  carrier_mixer_nco u_mix (
    .clk(clk), .rst_n(rst_n), .sample_valid(pv), .sample(dec2(rd_q)),
    .freq_word(fw), .load(nco_load), .phase_init(32'd0),
    .phase(carr_unused), .mix_i(mix_i), .mix_q(mix_q));

  code_nco u_code (
    .clk(clk), .rst_n(rst_n), .sample_valid(pv), .code_inc(inc),
    .load(nco_load), .phase_init(cp_init),
    .phase(cp_q), .phase_next(cp_next), .code_epoch(epoch_unused));

  code_ram u_ram (
    .clk(clk), .we(code_we), .waddr(code_waddr), .wdata(code_wdata),
    .e_idx(11'd0), .p_idx(cp_next[CODE_NCO_W-1 -: 11]), .l_idx(11'd0),
    .e_tap(e_unused), .p_tap(chip), .l_tap(l_unused));

  function automatic logic signed [CODE_NCO_W-1:0] aid_of(input logic signed [31:0] d);
    aid_of = CODE_NCO_W'((45'(d) * 45'sd2749) >>> CODE_AID_SHIFT);
  endfunction

  assign fw  = FREQ_WORD_IF + cur_dop;
  assign inc = CODE_NCO_INC_NOMINAL + aid_of(cur_dop);

  // 延迟线：dl[0] 为上一个样本的码片；第 j 路取 dl[4j-1]
  logic [WARM-1:0] dl;
  logic [N_LANES-1:0] tap;
  always_comb begin
    tap[0] = chip;
    for (int j = 1; j < N_LANES; j++) tap[j] = dl[4*j-1];
  end

  // 并行累加器
  logic signed [CORR_ACC_W-1:0] acc_i [N_LANES];
  logic signed [CORR_ACC_W-1:0] acc_q [N_LANES];
  logic [27:0]                  ncs   [N_LANES];
  logic [13:0]                  bc;            // 相干块内样本计数
  logic [1:0]                   blk;           // 已完成相干块数
  logic [BW-1:0]                k_total;

  function automatic logic [26:0] mag27(input logic signed [CORR_ACC_W-1:0] i,
                                        input logic signed [CORR_ACC_W-1:0] q);
    logic [26:0] ai, aq;
    ai = i[CORR_ACC_W-1] ? 27'(-{i[CORR_ACC_W-1], i}) : 27'(i);
    aq = q[CORR_ACC_W-1] ? 27'(-{q[CORR_ACC_W-1], q}) : 27'(q);
    mag27 = ai + (aq >> 1);
  endfunction

  wire acc_on   = pv && (kd >= BW'(WARM));
  wire blk_last = acc_on && (bc == 14'(SPM - 1));

  always_ff @(posedge clk) begin
    if (nco_load) begin
      dl <= '0;
      bc <= '0;
      blk <= '0;
      for (int j = 0; j < N_LANES; j++) begin
        acc_i[j] <= '0; acc_q[j] <= '0; ncs[j] <= '0;
      end
    end else if (pv) begin
      dl <= {dl[WARM-2:0], chip};
      if (acc_on) begin
        for (int j = 0; j < N_LANES; j++) begin
          logic signed [CORR_ACC_W-1:0] si, sq, ni, nq;
          si = tap[j] ? mix_i : -mix_i;
          sq = tap[j] ? mix_q : -mix_q;
          ni = acc_i[j] + si;
          nq = acc_q[j] + sq;
          if (blk_last) begin
            ncs[j]   <= ncs[j] + 28'(mag27(ni, nq));
            acc_i[j] <= '0;
            acc_q[j] <= '0;
          end else begin
            acc_i[j] <= ni;
            acc_q[j] <= nq;
          end
        end
        if (blk_last) begin
          bc  <= '0;
          blk <= blk + 2'd1;
        end else begin
          bc <= bc + 14'd1;
        end
      end
    end
  end

  // ---------------------------------------------------------------- 搜索状态机
  logic [7:0]                    bin;
  logic [LW+5:0]                 pass;           // 0..PASSES-1
  logic [12:0]                   h0;             // 本轮第 0 路的半码片序号（可 >= 4092）
  logic [LW:0]                   lane;
  logic                          fine;
  logic [2:0]                    fbin;
  logic [27:0]                   best_mag, fine_mag, best_mean;
  logic [11:0]                   best_h, fine_h;
  logic signed [31:0]            best_dop, fine_dop;
  logic                          best_in_bin;
  logic [39:0]                   bin_sum;
  logic signed [CODE_NCO_W+3:0]  px;             // 外推中间量（52 bit 有符号）
  logic [31:0]                   delta_s;
  logic [13:0]                   delta_mod_s;
  logic [31:0]                   pend;
  logic [CODE_NCO_W-1:0]         nco_run, inc_ho;

  assign k_total = BW'(WARM) + (nc == 2'd2 ? BW'(2 * SPM) : BW'(SPM));
  assign busy    = (st != S_IDLE);
  assign ready   = (st == S_READY);
  assign ho_phase = nco_run;

  // 第 lane 路的假设 = (h0 - lane) mod 4092
  wire signed [14:0] lane_h = $signed({2'b00, h0}) - $signed({1'b0, 14'(lane)});
  wire [11:0] h_mod = (lane_h < 0)                ? 12'(lane_h + 15'sd4092) :
                      (lane_h >= 15'sd4092)       ? 12'(lane_h - 15'sd4092) : 12'(lane_h);
  wire [12:0] h0_fine = 13'(best_h) + 13'(N_LANES / 2);
  wire signed [CODE_NCO_W+3:0] period_s = $signed({4'b0, CODE_NCO_PERIOD});

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= S_IDLE; done <= 1'b0; found <= 1'b0;
      wr_ptr <= '0; rd_addr <= '0; rd_en <= 1'b0; pv <= 1'b0; k <= '0; kd <= '0;
      nco_load <= 1'b0; cp_init <= '0; cur_dop <= '0;
      bin <= '0; pass <= '0; h0 <= '0; lane <= '0; fine <= 1'b0; fbin <= '0;
      best_mag <= '0; fine_mag <= '0; best_mean <= '0; best_h <= '0; fine_h <= '0;
      best_dop <= '0; fine_dop <= '0; best_in_bin <= 1'b0; bin_sum <= '0;
      px <= '0; delta_s <= '0; delta_mod_s <= '0; pend <= '0; nco_run <= '0; inc_ho <= '0;
      res_dop <= '0; res_h <= '0; res_peak <= '0; res_mean <= '0;
    end else begin
      done     <= 1'b0;
      nco_load <= 1'b0;
      rd_en    <= 1'b0;
      pv       <= rd_en;
      kd       <= rd_addr;     // 读数据拍对应的样本序号
      if (abort && st != S_IDLE) begin
        st <= S_IDLE; found <= 1'b0;
      end else begin
        case (st)
          S_IDLE: if (start) begin
            wr_ptr <= '0; found <= 1'b0;
            best_mag <= '0; best_mean <= '0; best_in_bin <= 1'b0; bin_sum <= '0;
            bin <= '0; pass <= '0; fine <= 1'b0;
            st <= S_CAPTURE;
          end

          S_CAPTURE: if (sample_valid) begin
            if (wr_ptr == BW'(BUF_DEPTH - 1)) st <= S_PASS_LOAD;
            wr_ptr <= wr_ptr + 1'b1;
          end

          S_PASS_LOAD: begin
            // 本轮覆盖 h0-N+1 .. h0；粗搜 h0 = pass*N + N-1；细搜让最佳假设落在中间路
            if (!fine) begin
              h0      <= 13'(pass * N_LANES + N_LANES - 1);
              cur_dop <= dop_min + $signed({24'd0, bin}) * dop_step;
              cp_init <= CODE_NCO_W'(pass * N_LANES + N_LANES - 1) * HALF_CHIP;
            end else begin
              h0      <= h0_fine;
              cur_dop <= best_dop + ($signed({29'd0, fbin}) - 32'sd2) * (dop_step >>> 2);
              cp_init <= CODE_NCO_W'(h0_fine) * HALF_CHIP;
            end
            nco_load <= 1'b1;
            k <= '0;
            st <= S_PASS_RUN;
          end

          S_PASS_RUN: begin
            if (k < k_total) begin
              rd_en   <= 1'b1;
              rd_addr <= k;
              k       <= k + 1'b1;
            end
            if (pv && kd == k_total - 1'b1) begin
              lane <= '0;
              st   <= S_SCAN;
            end
          end

          S_SCAN: begin
            if (!fine) begin
              if (ncs[lane[LW-1:0]] > best_mag) begin
                best_mag <= ncs[lane[LW-1:0]];
                best_h   <= h_mod;
                best_dop <= cur_dop;
                best_in_bin <= 1'b1;
              end
              bin_sum <= bin_sum + 40'(ncs[lane[LW-1:0]]);
            end else if (ncs[lane[LW-1:0]] > fine_mag) begin
              fine_mag <= ncs[lane[LW-1:0]];
              fine_h   <= h_mod;
              fine_dop <= cur_dop;
            end
            if (lane == (LW+1)'(N_LANES - 1)) st <= S_NEXT;
            lane <= lane + 1'b1;
          end

          S_NEXT: begin
            if (!fine) begin
              if (pass == (LW+6)'(PASSES - 1)) begin
                pass <= '0;
                if (best_in_bin) best_mean <= 28'(bin_sum >> 12);
                best_in_bin <= 1'b0;
                bin_sum <= '0;
                if (bin == n_bins - 8'd1) st <= S_DECIDE;
                else begin bin <= bin + 8'd1; st <= S_PASS_LOAD; end
              end else begin
                pass <= pass + 1'b1;
                st <= S_PASS_LOAD;
              end
            end else begin
              if (fbin == 3'd4) begin
                best_h <= fine_h; best_dop <= fine_dop; best_mag <= fine_mag;
                st <= S_PROP_MUL;
              end else begin
                fbin <= fbin + 3'd1;
                st <= S_PASS_LOAD;
              end
            end
          end

          S_DECIDE: begin
            res_peak <= best_mag;
            res_mean <= best_mean;
            if ({4'd0, best_mag} * 36'd16 > {8'd0, best_mean} * 36'(thr)) begin
              fine <= 1'b1; fbin <= '0;
              fine_mag <= '0; fine_h <= best_h; fine_dop <= best_dop;
              st <= S_PASS_LOAD;
            end else begin
              found <= 1'b0; done <= 1'b1;
              st <= S_IDLE;
            end
          end

          // ---- 外推：px = h·2^36 + (Δ mod 16368)·2^34 + Δ·aid
          S_PROP_MUL: begin
            delta_s     <= delta;
            delta_mod_s <= delta_mod;
            pend        <= sample_valid ? 32'd1 : 32'd0;   // 本拍样本未计入快照
            inc_ho      <= CODE_NCO_INC_NOMINAL + aid_of(best_dop);
            px <= $signed({4'b0, CODE_NCO_W'(best_h) << (CODE_NCO_FRAC_W - 1)})
                + $signed({4'b0, CODE_NCO_W'(delta_mod) << (CODE_NCO_FRAC_W - 3)})
                + $signed(52'($signed({1'b0, delta})) * 52'(aid_of(best_dop)));
            res_dop <= best_dop;
            res_h   <= best_h;
            st <= S_PROP_RED;
          end

          S_PROP_RED: begin
            if (sample_valid) pend <= pend + 32'd1;
            if (px >= period_s)  px <= px - period_s;
            else if (px < 0)     px <= px + period_s;
            else begin
              nco_run <= px[CODE_NCO_W-1:0];
              st <= S_CATCHUP;
            end
          end

          S_CATCHUP, S_READY: begin
            // 有新样本时先跟新样本；空拍时补回外推期间到达的样本
            if (sample_valid || pend != 0) begin
              logic [CODE_NCO_W:0] s;
              s = {1'b0, nco_run} + {1'b0, inc_ho};
              nco_run <= (s >= {1'b0, CODE_NCO_PERIOD}) ? s[CODE_NCO_W-1:0] - CODE_NCO_PERIOD
                                                        : s[CODE_NCO_W-1:0];
              if (!sample_valid) pend <= pend - 32'd1;
            end
            if (st == S_CATCHUP && pend == 0 && !sample_valid) begin
              found <= 1'b1; done <= 1'b1;
              st <= S_READY;
            end
            if (st == S_READY && ack) st <= S_IDLE;
          end

          default: st <= S_IDLE;
        endcase
      end
    end
  end

endmodule
