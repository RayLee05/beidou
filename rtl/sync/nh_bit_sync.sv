// =============================================================================
// nh_bit_sync.sv -- NH20 剥离与位同步（每通道一份）
//   输入：跟踪通道每个码周期的 Prompt I（dump_valid/dump_ms/i_p）
//   1) 保存最近 20 个 Prompt；每次 dump 后串行计算 corr = Σ nh_sign[k]·I[m-19+k]
//      （nh_sign = +1 当 NH 码片为 0，否则 -1；ICD 5.2.1 节）
//   2) 未同步：按位起点相位 p = (m+1) mod 20 累加 E[p] += |corr|；每累计 20*BS_BITS 个块
//      判决一次：E[best] >= 2*E[second] 则位同步，否则清零重来
//   3) 已同步：每当 (m+1) mod 20 == p，最近 20 个窗口构成一个数据位：
//      bit = (corr < 0)，bit_ms = 该位第一个窗口的标签 = m-19
//   极性由 Costas 环决定（180° 模糊），交给帧同步用前导码判定。
//   需求: REQ-SYN-001/002/003
// =============================================================================
`include "b1i_params.svh"

module nh_bit_sync #(
  parameter int BS_BITS = 10                     // 每个相位累计的块数
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         clear,      // 通道装载/释放时清零
  input  logic                         dump_valid,
  input  logic                         dump_partial,
  input  logic [31:0]                  dump_ms,
  input  logic [63:0]                  dump_sample_count,
  input  logic [47:0]                  dump_code_phase,
  input  logic signed [CORR_ACC_W-1:0] i_p,
  output logic                         synced,
  output logic [4:0]                   bit_phase,  // 位起点标签 mod 20
  output logic                         bit_valid,  // 单拍
  output logic                         bit_val,
  output logic [31:0]                  bit_ms,
  output logic [31:0]                  bit_mag,    // |corr|，位质量
  output logic [63:0]                  bit_end_sample,
  output logic [47:0]                  bit_end_phase
);

  localparam logic [19:0] NH = 20'b00000100110101001110;   // NH[0] 在最高位（ICD 顺序）

  logic signed [CORR_ACC_W-1:0] hist [20];     // hist[0] 最新
  logic [4:0]                   nhist;         // 已有完整窗口数（饱和 20）
  logic [4:0]                   m20;           // dump_ms mod 20
  logic [31:0]                  m_tag;
  logic [63:0]                  sample_tag;
  logic [47:0]                  phase_tag;
  logic [4:0]                   k;
  logic                         run;
  logic signed [CORR_ACC_W+5:0] corr;
  logic [39:0]                  E [20];
  logic [15:0]                  nblk;
  logic                         deciding;
  logic [4:0]                   di, best_i;
  logic [39:0]                  best_v, second_v;

  wire [4:0] p_start = (m20 == 5'd19) ? 5'd0 : m20 + 5'd1;   // (m+1) mod 20

  wire signed [CORR_ACC_W+5:0] term =
      NH[19 - k] ? -$signed((CORR_ACC_W+6)'(hist[19 - k])) : $signed((CORR_ACC_W+6)'(hist[19 - k]));
  wire signed [CORR_ACC_W+5:0] corr_n = corr + term;
  wire [31:0] corr_abs = corr_n[CORR_ACC_W+5] ? 32'(-corr_n) : 32'(corr_n);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < 20; i++) begin hist[i] <= '0; E[i] <= '0; end
      nhist <= '0; m20 <= '0; m_tag <= '0; k <= '0; run <= 1'b0; corr <= '0;
      nblk <= '0; deciding <= 1'b0; di <= '0; best_i <= '0; best_v <= '0; second_v <= '0;
      synced <= 1'b0; bit_phase <= '0; bit_valid <= 1'b0; bit_val <= 1'b0;
      bit_ms <= '0; bit_mag <= '0;
      sample_tag <= '0; phase_tag <= '0; bit_end_sample <= '0; bit_end_phase <= '0;
    end else if (clear) begin
      for (int i = 0; i < 20; i++) begin hist[i] <= '0; E[i] <= '0; end
      nhist <= '0; m20 <= '0; m_tag <= '0; k <= '0; run <= 1'b0; corr <= '0;
      nblk <= '0; deciding <= 1'b0; di <= '0; best_i <= '0; best_v <= '0; second_v <= '0;
      synced <= 1'b0; bit_phase <= '0; bit_valid <= 1'b0; bit_val <= 1'b0;
      bit_ms <= '0; bit_mag <= '0;
      sample_tag <= '0; phase_tag <= '0; bit_end_sample <= '0; bit_end_phase <= '0;
    end else begin
      bit_valid <= 1'b0;
      if (dump_valid) begin
        m20   <= (dump_ms == 32'd0) ? 5'd0 : ((m20 == 5'd19) ? 5'd0 : m20 + 5'd1);
        if (!dump_partial) begin
          for (int i = 19; i > 0; i--) hist[i] <= hist[i-1];
          hist[0] <= i_p;
          nhist   <= (nhist == 5'd20) ? nhist : nhist + 5'd1;
          m_tag   <= dump_ms;
          sample_tag <= dump_sample_count;
          phase_tag <= dump_code_phase;
          if (nhist >= 5'd19) begin
            run  <= 1'b1;
            k    <= '0;
            corr <= '0;
          end
        end
      end else if (run) begin
        // 串行累加：m20 已是本窗口标签 mod 20
        corr <= corr_n;
        if (k == 5'd19) begin
          run <= 1'b0;
          if (!synced) begin
            E[p_start] <= E[p_start] + 40'(corr_abs);
            if (nblk == 16'(20 * BS_BITS - 1)) begin
              nblk <= '0; deciding <= 1'b1; di <= '0; best_v <= '0; second_v <= '0;
            end else begin
              nblk <= nblk + 16'd1;
            end
          end else if (p_start == bit_phase) begin
            bit_valid <= 1'b1;
            bit_val   <= corr_n[CORR_ACC_W+5];
            bit_ms    <= m_tag - 32'd19;
            bit_mag   <= corr_abs;
            bit_end_sample <= sample_tag;
            bit_end_phase <= phase_tag;
          end
        end
        k <= k + 5'd1;
      end else if (deciding) begin
        // 逐个比较 20 个相位的累计能量
        if (E[di] > best_v) begin
          second_v <= best_v; best_v <= E[di]; best_i <= di;
        end else if (E[di] > second_v) begin
          second_v <= E[di];
        end
        if (di == 5'd19) begin
          deciding <= 1'b0;
          for (int i = 0; i < 20; i++) E[i] <= '0;
        end
        di <= di + 5'd1;
      end else if (!synced && best_v != 0 && di == 5'd20) begin
        if (best_v >= (second_v << 1)) begin
          synced <= 1'b1;
          bit_phase <= best_i;
        end
        best_v <= '0;
        di <= '0;
      end
    end
  end

endmodule
