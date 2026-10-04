// =============================================================================
// measurement_engine.sv -- 通道观测量快照与 MEAS 记录打包
//   每个完整 dump 更新该通道的活动观测；epoch_pulse 时冻结 12 路快照。
//   发射时刻：tx_ms = SOW*1000 + (dump_ms - anchor_ms) + 1
//   （+1：dump 标签是窗口起点，越界时卫星时间已再走 1 ms）
//   code_phase 为 dump 越界到历元的码片 Q(11.21)，不是 NCO 回绕残差。
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

  logic [N_CHANNELS-1:0][31:0] live_ms, live_dsc, live_dop, live_tx;
  logic [N_CHANNELS-1:0]       live_ok, live_lk, live_bs, live_tv, live_wv;
  logic [N_CHANNELS-1:0][3:0]  live_lc;
  logic [N_CHANNELS-1:0][12:0] live_wk;
  logic [N_CHANNELS-1:0][31:0] snap_ms, snap_cp, snap_dop, snap_tx;
  logic [N_CHANNELS-1:0]       snap_ok, snap_lk, snap_bs, snap_tv, snap_wv;
  logic [N_CHANNELS-1:0][3:0]  snap_lc;
  logic [N_CHANNELS-1:0][12:0] snap_wk;
  logic [N_CHANNELS-1:0][2:0]  snap_st;
  logic [N_CHANNELS-1:0][5:0]  snap_prn;
  logic [N_CHANNELS-1:0][7:0]  snap_gen;
  logic [31:0]                 snap_epoch;

  function automatic [31:0] cp_frac(input [31:0] ep_sc, input [31:0] dump_sc);
    logic [31:0] ds;
    ds = (ep_sc > dump_sc) ? (ep_sc - dump_sc) : 32'd0;
    if (ds >= SAMPLES_PER_MS) ds = SAMPLES_PER_MS - 32'd1;
    return ds << 18;
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      live_ok <= '0; live_dsc <= '0; snap_ok <= '0; n_valid <= '0; snap_epoch <= '0;
    end else begin
      for (int i = 0; i < N_CHANNELS; i++) begin
        if (dump_valid[i] && !dump_partial[i]) begin
          live_ms[i]  <= dump_ms[i];
          live_dsc[i] <= sample_count;
          live_dop[i] <= dop_word[i];
          live_lk[i]  <= locked[i];
          live_lc[i]  <= lock_cnt[i];
          live_bs[i]  <= bit_synced[i];
          live_tv[i]  <= anchor_valid[i] && locked[i];
          live_tx[i]  <= 32'(anchor_sow[i]) * 32'd1000
                       + (dump_ms[i] - anchor_ms[i]) + 32'd1;
          live_wk[i]  <= week[i];
          live_wv[i]  <= week_valid[i];
          live_ok[i]  <= locked[i];
        end
        if (ch_state[i] == CH_IDLE) live_ok[i] <= 1'b0;
      end
      if (epoch_pulse) begin
        snap_epoch <= epoch_id;
        snap_ok <= live_ok; snap_lk <= live_lk; snap_bs <= live_bs;
        snap_tv <= live_tv; snap_wv <= live_wv;
        snap_ms <= live_ms; snap_dop <= live_dop;
        snap_tx <= live_tx; snap_lc <= live_lc; snap_wk <= live_wk;
        for (int i = 0; i < N_CHANNELS; i++)
          snap_cp[i] <= cp_frac(sample_count,
            (dump_valid[i] && !dump_partial[i]) ? sample_count : live_dsc[i]);
        snap_st <= ch_state; snap_prn <= prn; snap_gen <= generation;
        n_valid <= 12'(live_ok[0]) + 12'(live_ok[1]) + 12'(live_ok[2])
                 + 12'(live_ok[3]) + 12'(live_ok[4]) + 12'(live_ok[5])
                 + 12'(live_ok[6]) + 12'(live_ok[7]) + 12'(live_ok[8])
                 + 12'(live_ok[9]) + 12'(live_ok[10]) + 12'(live_ok[11]);
      end
    end
  end

  always_comb begin
    for (int i = 0; i < N_CHANNELS; i++) begin
      meas_rec[i] = pack_meas(4'(i), snap_prn[i], snap_gen[i], snap_epoch,
                              snap_tx[i], snap_cp[i], snap_dop[i], snap_ms[i],
                              snap_ok[i], snap_lk[i], snap_bs[i], snap_tv[i],
                              snap_st[i], snap_lc[i], snap_wk[i], snap_wv[i]);
    end
  end

endmodule
