// =============================================================================
// acquisition_engine.sv -- 捕获搜索引擎（码相位串行扫描）
//   给定一个多普勒频率字，按 code_start / code_step 逐个假设做 1 ms 相干积分，
//   用 |I| + |Q|/2 作判决量，记录峰值并在超过门限时置 found。
//   混频、码 NCO、码 RAM 全部复用跟踪通道的同一批模块（一份 RTL，两处例化）。
//   说明：码相位串行扫描一轮很慢（2046 假设 x 多普勒位 = 数十秒），
//         先做功能正确版本，提速方案见 docs/ARCHITECTURE.md 第 8.5 节。
//   需求: REQ-ACQ-001/002/003/004/006
// =============================================================================
`include "b1i_params.svh"

module acquisition_engine (
  input  logic                          clk,
  input  logic                          rst_n,
  input  logic                          sample_valid,
  input  logic signed [SAMPLE_W-1:0]    sample,
  // 任务配置
  input  logic                          start,
  input  logic [FREQ_WORD_W-1:0]        doppler_word,
  input  logic [CODE_PHASE_W-1:0]       code_start,
  input  logic [CODE_PHASE_W-1:0]       code_step,
  input  logic [15:0]                   num_hyp,
  input  logic signed [CORR_ACC_W-1:0]  threshold,
  // PRN 码装载（码表按 ICD 装入）
  input  logic                          code_we,
  input  logic [10:0]                   code_waddr,
  input  logic                          code_wdata,
  // 结果
  output logic                          busy,
  output logic                          done,
  output logic                          found,
  output logic [CODE_PHASE_W-1:0]       found_code_phase,
  output logic signed [CORR_ACC_W-1:0]  peak_mag,
  output logic [15:0]                   hyp_index
);

  localparam int CNT_W = 15;

  logic signed [SAMPLE_W+CARR_LUT_DATA_W-1:0] mix_i, mix_q;
  logic [NCO_PHASE_W-1:0]      carr_phase;
  logic [CODE_PHASE_W-1:0]     code_phase;
  logic [10:0]                 chip_idx, e_idx, l_idx;
  logic                        p_tap, e_tap, l_tap;
  logic                        pending_first;
  logic                        hyp_load;
  logic signed [CORR_ACC_W-1:0] i_acc, q_acc;
  logic [CNT_W-1:0]            cnt;
  logic                        busy_q;
  logic [15:0]                 hyp_q;
  logic [CODE_PHASE_W-1:0]     cp_init;

  wire signed [CODE_PHASE_W-1:0] code_inc_fixed = CODE_INC_NOMINAL;

  function automatic [CORR_ACC_W:0] absq(input logic signed [CORR_ACC_W-1:0] v);
    logic signed [CORR_ACC_W:0] vx;
    begin
      vx   = v;
      absq = vx[CORR_ACC_W] ? -vx : vx;
    end
  endfunction

  assign busy      = busy_q;
  assign hyp_index = hyp_q;
  assign hyp_load  = sample_valid & pending_first;

  carrier_mixer_nco u_mix (
    .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid), .sample(sample),
    .freq_word(doppler_word), .load(hyp_load), .phase_init(32'd0),
    .phase(carr_phase), .mix_i(mix_i), .mix_q(mix_q));

  code_nco u_code (
    .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid),
    .code_inc(code_inc_fixed), .load(hyp_load), .phase_init(cp_init),
    .code_phase(code_phase), .chip_idx(chip_idx), .code_epoch_tick());

  code_ram u_ram (
    .clk(clk), .rst_n(rst_n), .we(code_we), .waddr(code_waddr), .wdata(code_wdata),
    .chip_idx(chip_idx), .spacing(4'd1),
    .e_tap(e_tap), .p_tap(p_tap), .l_tap(l_tap), .e_idx(e_idx), .l_idx(l_idx));

  wire signed [CORR_ACC_W-1:0] s_i = p_tap ? mix_i : -mix_i;
  wire signed [CORR_ACC_W-1:0] s_q = p_tap ? mix_q : -mix_q;
  wire signed [CORR_ACC_W-1:0] i_fin = i_acc + s_i;
  wire signed [CORR_ACC_W-1:0] q_fin = q_acc + s_q;
  wire [CORR_ACC_W:0]          mag   = absq(i_fin) + (absq(q_fin) >>> 1);
  wire signed [CORR_ACC_W-1:0] mag_s = mag[CORR_ACC_W-1:0];
  wire                         last  = (cnt == SAMPLES_PER_MS - 1);
  wire                         last_hyp = (hyp_q + 16'd1 >= num_hyp);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy_q <= 1'b0; done <= 1'b0; found <= 1'b0; pending_first <= 1'b0;
      hyp_q <= 16'd0; cnt <= '0; i_acc <= '0; q_acc <= '0;
      peak_mag <= '0; found_code_phase <= '0; cp_init <= '0;
    end else begin
      done <= 1'b0;
      if (start & ~busy_q) begin
        busy_q <= 1'b1; found <= 1'b0; pending_first <= 1'b1;
        hyp_q <= 16'd0; cnt <= '0; i_acc <= '0; q_acc <= '0;
        peak_mag <= '0; cp_init <= code_start;
      end else if (busy_q & sample_valid) begin
        if (pending_first) begin
          i_acc <= s_i; q_acc <= s_q; cnt <= {{(CNT_W-1){1'b0}}, 1'b1};
          pending_first <= 1'b0;
        end else if (last) begin
          if (mag_s > peak_mag) begin
            peak_mag <= mag_s;
            found_code_phase <= cp_init;
          end
          if (mag_s > threshold) found <= 1'b1;
          if (last_hyp) begin
            busy_q <= 1'b0; done <= 1'b1;
          end else begin
            hyp_q <= hyp_q + 16'd1;
            cp_init <= cp_init + code_step;
            cnt <= '0; i_acc <= '0; q_acc <= '0; pending_first <= 1'b1;
          end
        end else begin
          i_acc <= i_acc + s_i; q_acc <= q_acc + s_q; cnt <= cnt + 1'b1;
        end
      end
    end
  end

endmodule
