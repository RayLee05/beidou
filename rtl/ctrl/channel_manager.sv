// =============================================================================
// channel_manager.sv -- 搜索表调度、捕获移交、通道分配与失锁释放
//   空闲时从 prn_list 取下一颗未占用卫星 → 写捕获码 RAM → 启动 acquisition；
//   命中则分配空闲通道、再写该通道码 RAM、init_load + ack；
//   牵引超时 / 持续失锁则释放通道并记 STATUS 事件。
//   force_alloc 供仿真/调试跳过捕获，只走“写码 + 装载”。
//   需求: REQ-ACQ-005/006, REQ-SYS-001..003
// =============================================================================
`include "b1i_params.svh"
`include "b1i_records.svh"

module channel_manager #(parameter bit AUTO_SCAN = 1'b0) (
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic                       run,
  input  logic                       search_enable, // AUTO_SCAN: stop searching at EOF
  input  logic                       ms_tick,
  input  logic [3:0]                 n_prns,
  input  logic [11:0][PRN_W-1:0]     prn_list,
  input  logic [31:0]                pullin_to,
  input  logic [31:0]                lost_to,
  input  logic [31:0]                bit_sync_to,
  input  logic [31:0]                frame_sync_to,
  // 捕获
  output logic                       acq_start,
  output logic                       acq_abort,
  output logic                       acq_ack,
  input  logic                       acq_busy,
  input  logic                       acq_done,
  input  logic                       acq_found,
  input  logic                       acq_ready,
  output logic [PRN_W-1:0]           acq_prn,
  // 码发生器
  output logic                       gen_start,
  output logic [PRN_W-1:0]           gen_prn,
  input  logic                       gen_done,
  input  logic                       gen_busy,
  input  logic                       gen_bad,
  output logic                       gen_to_acq,
  output logic [CHANNEL_ID_W-1:0]    gen_ch,
  // 强制装载（调试）
  input  logic                       force_alloc,
  input  logic [CHANNEL_ID_W-1:0]    force_ch,
  input  logic [PRN_W-1:0]           force_prn,
  output logic                       force_handover, // 与强制装载的 ch_init_load 同拍
  // 通道
  input  logic [N_CHANNELS-1:0]      ch_locked,
  input  logic [N_CHANNELS-1:0]      ch_bit_synced,
  input  logic [N_CHANNELS-1:0]      ch_frame_synced,
  output logic [N_CHANNELS-1:0]      ch_enable,
  output logic [N_CHANNELS-1:0]      ch_init_load,
  output logic [N_CHANNELS-1:0]      ch_clear,
  output logic [N_CHANNELS-1:0][PRN_W-1:0] ch_prn,
  output logic [N_CHANNELS-1:0][2:0] ch_state,
  output logic [N_CHANNELS-1:0][7:0] ch_gen,
  // 事件（valid/ready：下游未接手时保持）
  output logic                       ev_valid,
  input  logic                       ev_ready,
  output logic [3:0]                 ev_code,
  output logic [CHANNEL_ID_W-1:0]    ev_ch,
  output logic [PRN_W-1:0]           ev_prn,
  output logic [7:0]                 ev_gen,
  output logic [31:0]                ev_a1
);

  typedef enum logic [3:0] {
    S_IDLE, S_PICK, S_GEN_ACQ, S_ACQ_GO, S_ACQ_WAIT,
    S_ALLOC, S_GEN_CH, S_HANDOVER, S_FORCE_GEN
  } st_t;
  st_t st;

  logic [3:0]  scan;
  logic [5:0]  auto_prn;
  logic [3:0]  tgt;
  logic [5:0]  cur_prn;
  logic        hit_latched;
  logic [N_CHANNELS-1:0][31:0] tmr, nav_tmr;
  logic [N_CHANNELS-1:0]       to_sent, saw_bit;

  // 每通道一条挂起 + 1 条无通道事件（捕获未命中），避免同拍覆盖
  logic [N_CHANNELS:0]         pe_v;
  logic [N_CHANNELS:0][3:0]    pe_code, pe_ch;
  logic [N_CHANNELS:0][5:0]    pe_prn;
  logic [N_CHANNELS:0][7:0]    pe_gen;
  logic [N_CHANNELS:0][31:0]   pe_a1;

  function automatic logic prn_used(input logic [5:0] p);
    logic u;
    u = 1'b0;
    for (int i = 0; i < N_CHANNELS; i++)
      if (ch_state[i] != CH_IDLE && ch_prn[i] == p) u = 1'b1;
    return u;
  endfunction

  function automatic logic [3:0] first_free();
    logic [3:0] f;
    f = 4'd15;
    for (int i = N_CHANNELS - 1; i >= 0; i--)
      if (ch_state[i] == CH_IDLE) f = 4'(i);
    return f;
  endfunction

  logic        ev_hold;
  logic        ev_take;

  function automatic logic [4:0] first_pe();
    logic [4:0] f;
    f = 5'd31;
    for (int i = N_CHANNELS; i >= 0; i--)
      if (pe_v[i]) f = 5'(i);
    return f;
  endfunction

  assign ev_valid = ev_hold;
  assign ev_take  = ev_hold && ev_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= S_IDLE;
      scan <= '0; tgt <= '0; cur_prn <= '0; hit_latched <= 1'b0;
      auto_prn <= 6'd1;
      acq_start <= 1'b0; acq_abort <= 1'b0; acq_ack <= 1'b0; acq_prn <= '0;
      gen_start <= 1'b0; gen_prn <= '0; gen_to_acq <= 1'b0; gen_ch <= '0;
      ch_enable <= '0; ch_init_load <= '0; ch_clear <= '0;
      force_handover <= 1'b0;
      ev_hold <= 1'b0; ev_code <= '0; ev_ch <= '0; ev_prn <= '0; ev_gen <= '0; ev_a1 <= '0;
      pe_v <= '0;
      for (int i = 0; i < N_CHANNELS; i++) begin
        ch_prn[i] <= '0; ch_state[i] <= CH_IDLE; ch_gen[i] <= '0; tmr[i] <= '0;
        nav_tmr[i] <= '0; to_sent[i] <= 1'b0; saw_bit[i] <= 1'b0;
      end
    end else begin
      acq_start <= 1'b0;
      acq_abort <= 1'b0;
      acq_ack   <= 1'b0;
      gen_start <= 1'b0;
      ch_init_load <= '0;
      ch_clear     <= '0;
      force_handover <= 1'b0;
      if (ev_take) ev_hold <= 1'b0;
      if ((!ev_hold || ev_take) && first_pe() != 5'd31) begin
        ev_hold <= 1'b1;
        ev_code <= pe_code[first_pe()];
        ev_ch   <= pe_ch[first_pe()];
        ev_prn  <= pe_prn[first_pe()];
        ev_gen  <= pe_gen[first_pe()];
        ev_a1   <= pe_a1[first_pe()];
        pe_v[first_pe()] <= 1'b0;
      end

      if (!run) begin
        st <= S_IDLE;
        pe_v <= '0;
        acq_abort <= acq_busy;
        for (int i = 0; i < N_CHANNELS; i++) begin
          if (ch_state[i] != CH_IDLE) begin
            ch_state[i]  <= CH_IDLE;
            ch_enable[i] <= 1'b0;
            ch_clear[i]  <= 1'b1;
          end
        end
      end else begin
        // ---- 通道监督（1 ms）
        if (ms_tick) begin
          for (int i = 0; i < N_CHANNELS; i++) begin
            if (ch_state[i] == CH_PULLIN) begin
              tmr[i] <= tmr[i] + 32'd1;
              if (ch_locked[i]) begin
                ch_state[i] <= CH_TRACK;
                nav_tmr[i] <= '0; to_sent[i] <= 1'b0; saw_bit[i] <= 1'b0;
                pe_v[i] <= 1'b1; pe_code[i] <= EV_LOCKED; pe_ch[i] <= 4'(i);
                pe_prn[i] <= ch_prn[i]; pe_gen[i] <= ch_gen[i]; pe_a1[i] <= 32'd0;
              end else if (tmr[i] + 32'd1 >= pullin_to) begin
                ch_state[i]  <= CH_IDLE;
                ch_enable[i] <= 1'b0;
                ch_clear[i]  <= 1'b1;
                pe_v[i] <= 1'b1; pe_code[i] <= EV_RELEASED; pe_ch[i] <= 4'(i);
                pe_prn[i] <= ch_prn[i]; pe_gen[i] <= ch_gen[i]; pe_a1[i] <= 32'd1;
              end
            end else if (ch_state[i] == CH_TRACK) begin
              if (!ch_locked[i]) begin
                ch_state[i] <= CH_LOST;
                tmr[i]      <= '0;
                pe_v[i] <= 1'b1; pe_code[i] <= EV_LOST; pe_ch[i] <= 4'(i);
                pe_prn[i] <= ch_prn[i]; pe_gen[i] <= ch_gen[i]; pe_a1[i] <= 32'd0;
              end else if (!ch_bit_synced[i]) begin
                saw_bit[i] <= 1'b0;
                nav_tmr[i] <= nav_tmr[i] + 32'd1;
                if (nav_tmr[i] + 32'd1 >= bit_sync_to && !to_sent[i]) begin
                  to_sent[i] <= 1'b1;
                  pe_v[i] <= 1'b1; pe_code[i] <= EV_NAV_TIMEOUT; pe_ch[i] <= 4'(i);
                  pe_prn[i] <= ch_prn[i]; pe_gen[i] <= ch_gen[i]; pe_a1[i] <= 32'd1;
                end
              end else if (!ch_frame_synced[i]) begin
                if (!saw_bit[i]) begin
                  saw_bit[i] <= 1'b1;
                  nav_tmr[i] <= '0;
                  to_sent[i] <= 1'b0;
                end else begin
                  nav_tmr[i] <= nav_tmr[i] + 32'd1;
                  if (nav_tmr[i] + 32'd1 >= frame_sync_to && !to_sent[i]) begin
                    to_sent[i] <= 1'b1;
                    pe_v[i] <= 1'b1; pe_code[i] <= EV_NAV_TIMEOUT; pe_ch[i] <= 4'(i);
                    pe_prn[i] <= ch_prn[i]; pe_gen[i] <= ch_gen[i]; pe_a1[i] <= 32'd2;
                  end
                end
              end else begin
                nav_tmr[i] <= '0; to_sent[i] <= 1'b0;
              end
            end else if (ch_state[i] == CH_LOST) begin
              tmr[i] <= tmr[i] + 32'd1;
              if (ch_locked[i]) begin
                ch_state[i] <= CH_TRACK;
                pe_v[i] <= 1'b1; pe_code[i] <= EV_RELOCKED; pe_ch[i] <= 4'(i);
                pe_prn[i] <= ch_prn[i]; pe_gen[i] <= ch_gen[i]; pe_a1[i] <= 32'd0;
              end else if (tmr[i] + 32'd1 >= lost_to) begin
                ch_state[i]  <= CH_IDLE;
                ch_enable[i] <= 1'b0;
                ch_clear[i]  <= 1'b1;
                pe_v[i] <= 1'b1; pe_code[i] <= EV_RELEASED; pe_ch[i] <= 4'(i);
                pe_prn[i] <= ch_prn[i]; pe_gen[i] <= ch_gen[i]; pe_a1[i] <= 32'd2;
              end
            end
          end
        end
        if (AUTO_SCAN && !search_enable) begin
          st <= S_IDLE;
          acq_abort <= acq_busy;
          hit_latched <= 1'b0;
        end else case (st)
          S_IDLE: begin
            if (force_alloc && force_prn != 0 && force_ch < N_CHANNELS
                && ch_state[force_ch] == CH_IDLE) begin
              tgt         <= force_ch;
              cur_prn     <= force_prn;
              gen_prn     <= force_prn;
              gen_to_acq  <= 1'b0;
              gen_ch      <= force_ch;
              gen_start   <= 1'b1;
              st          <= S_FORCE_GEN;
            end else if ((AUTO_SCAN || n_prns != 4'd0) && first_free() != 4'd15 && !acq_busy) begin
              st <= S_PICK;
            end
          end

          S_PICK: begin
            if (AUTO_SCAN) begin
              auto_prn <= (auto_prn == 6'd63) ? 6'd1 : auto_prn + 6'd1;
              if (!prn_used(auto_prn)) begin
                cur_prn <= auto_prn; acq_prn <= auto_prn; gen_prn <= auto_prn;
                gen_to_acq <= 1'b1; gen_start <= 1'b1; st <= S_GEN_ACQ;
              end
            end else if (scan >= n_prns) begin
              scan <= '0;
              st   <= S_IDLE;
            end else if (prn_list[scan] != '0 && !prn_used(prn_list[scan])) begin
              cur_prn    <= prn_list[scan];
              acq_prn    <= prn_list[scan];
              gen_prn    <= prn_list[scan];
              gen_to_acq <= 1'b1;
              gen_start  <= 1'b1;
              scan       <= (scan + 4'd1 >= n_prns) ? 4'd0 : scan + 4'd1;
              st         <= S_GEN_ACQ;
            end else begin
              scan <= (scan + 4'd1 >= n_prns) ? 4'd0 : scan + 4'd1;
              if (scan + 4'd1 >= n_prns) st <= S_IDLE;
            end
          end

          S_GEN_ACQ: begin
            if (gen_bad) st <= S_IDLE;
            else if (gen_done) begin
              acq_start <= 1'b1;
              st        <= S_ACQ_GO;
            end
          end

          S_ACQ_GO: st <= S_ACQ_WAIT;

          S_ACQ_WAIT: begin
            if (acq_done) begin
              if (acq_found) begin
                hit_latched <= 1'b1;
                st          <= S_ALLOC;
              end else begin
                pe_v[N_CHANNELS] <= 1'b1;
                pe_code[N_CHANNELS] <= EV_ACQ_MISS;
                pe_ch[N_CHANNELS] <= 4'd0;
                pe_prn[N_CHANNELS] <= cur_prn;
                pe_gen[N_CHANNELS] <= 8'd0;
                pe_a1[N_CHANNELS] <= 32'd0;
                st <= S_IDLE;
              end
            end
          end

          S_ALLOC: begin
            if (first_free() == 4'd15) begin
              acq_ack <= 1'b1;
              st      <= S_IDLE;
            end else begin
              tgt        <= first_free();
              gen_prn    <= cur_prn;
              gen_to_acq <= 1'b0;
              gen_ch     <= first_free();
              gen_start  <= 1'b1;
              st         <= S_GEN_CH;
            end
          end

          S_GEN_CH: begin
            if (gen_done) st <= S_HANDOVER;
          end

          S_HANDOVER: begin
            if (acq_ready || hit_latched) begin
              ch_prn[tgt]       <= cur_prn;
              ch_state[tgt]     <= CH_PULLIN;
              ch_enable[tgt]    <= 1'b1;
              ch_init_load[tgt] <= 1'b1;
              ch_gen[tgt]       <= ch_gen[tgt] + 8'd1;
              tmr[tgt]          <= '0;
              acq_ack           <= 1'b1;
              hit_latched       <= 1'b0;
              pe_v[tgt] <= 1'b1; pe_code[tgt] <= EV_ACQ_FOUND; pe_ch[tgt] <= tgt;
              pe_prn[tgt] <= cur_prn; pe_gen[tgt] <= ch_gen[tgt] + 8'd1; pe_a1[tgt] <= 32'd0;
              nav_tmr[tgt] <= '0; to_sent[tgt] <= 1'b0; saw_bit[tgt] <= 1'b0;
              st <= S_IDLE;
            end
          end

          S_FORCE_GEN: begin
            if (gen_bad && !gen_start) st <= S_IDLE;
            else if (gen_done) begin
              ch_prn[tgt]       <= cur_prn;
              ch_state[tgt]     <= CH_PULLIN;
              ch_enable[tgt]    <= 1'b1;
              ch_init_load[tgt] <= 1'b1;
              force_handover    <= 1'b1;
              ch_gen[tgt]       <= ch_gen[tgt] + 8'd1;
              tmr[tgt]          <= '0;
              nav_tmr[tgt]      <= '0; to_sent[tgt] <= 1'b0; saw_bit[tgt] <= 1'b0;
              st                <= S_IDLE;
            end
          end

          default: st <= S_IDLE;
        endcase
      end
    end
  end

endmodule
