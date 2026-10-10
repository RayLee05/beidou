// =============================================================================
// measurement_engine.sv -- 通道观测量快照与 MEAS 记录打包
//   每个完整 dump 更新该通道的活动观测；epoch_pulse 时冻结 12 路快照。
//   发射时刻：tx_ms = SOW*1000 + (dump_ms - anchor_ms) + 1
//   （+1：dump 标签是窗口起点，越界时卫星时间已再走 1 ms）
//   code_phase 直接冻结通道 NCO 的 Q11.21 相位，保留越界残差及码率修正。
//   伪距由软件用 (t_rx - t_tx)*c 计算，RTL 不输出米制伪距。
//   需求: REQ-MEAS-001/002
// =============================================================================
`include "b1i_params.svh"
`include "b1i_records.svh"

module measurement_engine (
  input  logic                            clk,
  input  logic                            rst_n,
  input  logic                            epoch_pulse,
  input  logic [31:0]                     epoch_id,
  input  logic [31:0]                     sample_count,
  input  logic [N_CHANNELS-1:0]           dump_valid,
  input  logic [N_CHANNELS-1:0]           dump_partial,
  input  logic [N_CHANNELS-1:0][31:0]     dump_ms,
  input  logic [N_CHANNELS-1:0][31:0]     code_phase,
  input  logic [N_CHANNELS-1:0][31:0]     dop_word,
  input  logic [N_CHANNELS-1:0]           locked,
  input  logic [N_CHANNELS-1:0][3:0]      lock_cnt,
  input  logic [N_CHANNELS-1:0]           bit_synced,
  input  logic [N_CHANNELS-1:0]           anchor_valid,
  input  logic [N_CHANNELS-1:0][31:0]     anchor_ms,
  input  logic [N_CHANNELS-1:0][19:0]     anchor_sow,
  input  logic [N_CHANNELS-1:0][12:0]     week,
  input  logic [N_CHANNELS-1:0]           week_valid,
  input  logic [N_CHANNELS-1:0][2:0]      ch_state,
  input  logic [N_CHANNELS-1:0][PRN_W-1:0] prn,
  input  logic [N_CHANNELS-1:0][7:0]      generation,
  output logic [N_CHANNELS-1:0][255:0]    meas_rec,
  output logic [11:0]                     n_valid
);

  // 仅完整窗口可更新观测；PRN/generation 一起缓存，防止通道重分配串用旧值。
  logic [N_CHANNELS-1:0][31:0] live_ms, live_dsc, live_dop;
  logic [N_CHANNELS-1:0][7:0] live_gen;
  logic [N_CHANNELS-1:0][PRN_W-1:0] live_prn;
  logic [N_CHANNELS-1:0] live_ok;
  logic [N_CHANNELS-1:0][31:0] next_ms, next_dsc, next_dop;
  logic [N_CHANNELS-1:0][7:0] next_gen;
  logic [N_CHANNELS-1:0][PRN_W-1:0] next_prn;
  logic [N_CHANNELS-1:0] next_ok, obs_ok;
  logic [N_CHANNELS-1:0][31:0] tx_ms;
  logic [N_CHANNELS-1:0][12:0] tx_week;
  logic [11:0] valid_count;
  logic [N_CHANNELS-1:0][255:0] snap_rec;

  always_comb begin
    next_ms = live_ms; next_dsc = live_dsc; next_dop = live_dop;
    next_gen = live_gen; next_prn = live_prn; next_ok = live_ok;
    valid_count = '0;
    for (int i = 0; i < N_CHANNELS; i++) begin
      if (dump_valid[i] && !dump_partial[i]) begin
        next_ms[i] = dump_ms[i];
        next_dsc[i] = sample_count;
        next_dop[i] = dop_word[i];
        next_gen[i] = generation[i];
        next_prn[i] = prn[i];
        next_ok[i] = 1'b1;
      end
      if (ch_state[i] == CH_IDLE || ch_state[i] == CH_LOST || !locked[i]
          || next_gen[i] != generation[i] || next_prn[i] != prn[i]
          || (sample_count - next_dsc[i]) >= 32'(2 * SAMPLES_PER_MS))
        next_ok[i] = 1'b0;
      obs_ok[i] = next_ok[i] && bit_synced[i] && anchor_valid[i];
      valid_count = valid_count + 12'(obs_ok[i]);
      tx_ms[i] = 32'(anchor_sow[i]) * 32'd1000
                 + (next_ms[i] - anchor_ms[i]) + 32'd1;
      tx_week[i] = week[i];
      // SOW 字段是周内时间，最后一个子帧的窗口可能跨周。
      if (tx_ms[i] >= 32'd604800000) begin
        tx_ms[i] = tx_ms[i] - 32'd604800000;
        tx_week[i] = week[i] + 13'd1;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      live_ms <= '0; live_dsc <= '0; live_dop <= '0;
      live_gen <= '0; live_prn <= '0; live_ok <= '0;
      snap_rec <= '0; n_valid <= '0;
    end else begin
      live_ms <= next_ms; live_dsc <= next_dsc; live_dop <= next_dop;
      live_gen <= next_gen; live_prn <= next_prn; live_ok <= next_ok;
      if (epoch_pulse) begin
        n_valid <= valid_count;
        for (int i = 0; i < N_CHANNELS; i++) begin
          // 同拍 dump 先旁路再冻结，时间、频率、码相位属于同一观测。
          snap_rec[i] <= pack_meas(4'(i), prn[i], generation[i], epoch_id,
            obs_ok[i] ? tx_ms[i] : 32'd0,
            next_ok[i] ? code_phase[i] : 32'd0,
            next_ok[i] ? next_dop[i] : 32'd0,
            next_ok[i] ? next_ms[i] : 32'd0,
            obs_ok[i], locked[i], bit_synced[i], obs_ok[i],
            ch_state[i], lock_cnt[i], tx_week[i], week_valid[i] && obs_ok[i]);
        end
      end
    end
  end

  assign meas_rec = snap_rec;
endmodule
