// =============================================================================
// b1i_rx_top.sv -- 12 通道 B1I 数字核心顶层
//   字节解包（或 SRAM）→ 公共时基 → 1 个捕获引擎 + 12 个 channel_slice
//   → 历元/测量/电文/状态记录 FIFO。
//   配置用 addr/wdata 寄存器；force_alloc 可跳过捕获做通道级仿真。
//   需求: REQ-SYS-001..004, REQ-IO-001/002, REQ-MEAS-001..003
// =============================================================================
`include "b1i_params.svh"
`include "b1i_records.svh"

module b1i_rx_top #(
  parameter int N_LANES   = 64,
  parameter int BUF_DEPTH = 33024,
  parameter bit USE_SRAM  = 1'b0
) (
  input  logic                       clk,
  input  logic                       rst_n,
  // 文件/字节输入（USE_SRAM=0）
  input  logic                       byte_valid,
  input  logic [7:0]                 data_byte,
  output logic                       byte_ready,
  // SRAM 输入（USE_SRAM=1）
  input  logic                       sram_run,
  input  logic                       sram_pace_en,
  input  logic [31:0]                sram_pace_inc,
  input  logic [31:0]                sram_sample_total,
  output logic                       sram_rd,
  output logic [23:0]                sram_addr,
  input  logic [7:0]                 sram_rdata,
  input  logic                       sram_rvalid,
  output logic                       sram_done,
  // 配置
  input  logic                       cfg_valid,
  input  logic [7:0]                 cfg_addr,
  input  logic [31:0]                cfg_wdata,
  output logic                       cfg_ready,
  output logic [31:0]                cfg_rdata,
  // 记录
  output logic                       rec_valid,
  input  logic                       rec_ready,
  output logic [255:0]               rec_data,
  output logic                       rec_last,
  // 状态
  output logic [N_CHANNELS-1:0]      ch_locked,
  output logic [N_CHANNELS-1:0]      ch_bit_valid,
  output logic [N_CHANNELS-1:0]      ch_nav_valid,
  output logic                       error_valid,
  output logic [31:0]                error_code
);

  assign cfg_ready = 1'b1;
  // 每个历元包最后一条 MEAS（CH11）拉 rec_last，供下游划界
  assign rec_last = rec_valid && (rec_data[255:252] == REC_MEAS)
                 && (rec_data[251:248] == 4'(N_CHANNELS - 1));

  // ---------------------------------------------------------------- 配置寄存器
  logic        run;
  logic [3:0]  n_prns;
  logic [11:0][PRN_W-1:0] prn_list;
  logic signed [31:0] dop_min, dop_step;
  logic [7:0]  n_bins, thr;
  logic [1:0]  nc;
  logic [31:0] pullin_to, lost_to, epoch_ms, bit_sync_to, frame_sync_to, sow0_ms;
  logic        force_alloc;
  logic [3:0]  force_ch;
  logic [5:0]  force_prn;
  logic [47:0] force_phase;
  logic signed [31:0] force_dop;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      run <= 1'b0; n_prns <= 4'd0; prn_list <= '0;
      dop_min <= -32'sd2621440; dop_step <= 32'sd131072; // ≈ −10 kHz, 500 Hz
      n_bins <= 8'd41; nc <= 2'd1; thr <= 8'h28;
      pullin_to <= 32'd2000; lost_to <= 32'd2000; epoch_ms <= 32'd1000;
      bit_sync_to <= 32'd2000; frame_sync_to <= 32'd34000; sow0_ms <= 32'd0;
      force_alloc <= 1'b0; force_ch <= '0; force_prn <= 6'd1;
      force_phase <= '0; force_dop <= '0;
    end else begin
      force_alloc <= 1'b0;
      if (cfg_valid) begin
        case (cfg_addr)
          8'h00: run      <= cfg_wdata[0];
          8'h01: n_prns   <= cfg_wdata[3:0];
          8'h02: prn_list[cfg_wdata[3:0]] <= cfg_wdata[13:8];
          8'h10: dop_min  <= cfg_wdata;
          8'h11: dop_step <= cfg_wdata;
          8'h12: begin n_bins <= cfg_wdata[7:0]; nc <= cfg_wdata[9:8]; thr <= cfg_wdata[17:10]; end
          8'h13: pullin_to <= cfg_wdata;
          8'h14: lost_to   <= cfg_wdata;
          8'h15: epoch_ms  <= cfg_wdata;
          8'h16: bit_sync_to   <= cfg_wdata;
          8'h17: frame_sync_to <= cfg_wdata;
          8'h18: sow0_ms       <= cfg_wdata;
          8'h20: begin
            force_alloc <= cfg_wdata[0];
            force_ch    <= cfg_wdata[7:4];
            force_prn   <= cfg_wdata[13:8];
          end
          8'h21: force_phase[31:0]  <= cfg_wdata;
          8'h22: force_phase[47:32] <= cfg_wdata[15:0];
          8'h23: force_dop          <= cfg_wdata;
          default: ;
        endcase
      end
    end
  end

  always_comb begin
    case (cfg_addr)
      8'h00: cfg_rdata = {31'd0, run};
      8'h01: cfg_rdata = {28'd0, n_prns};
      8'h15: cfg_rdata = epoch_ms;
      8'h18: cfg_rdata = sow0_ms;
      default: cfg_rdata = 32'd0;
    endcase
  end

  // ---------------------------------------------------------------- 样本流
  logic                       sample_valid;
  logic signed [SAMPLE_W-1:0] sample;
  logic                       input_done;
  logic                       unpack_ready;
  logic                       unpack_sv;
  logic signed [SAMPLE_W-1:0] unpack_s;
  logic                       sram_sv;
  logic signed [SAMPLE_W-1:0] sram_s;

  sample_unpacker u_unpack (
    .clk(clk), .rst_n(rst_n), .byte_valid(byte_valid & ~USE_SRAM),
    .data_byte(data_byte), .byte_ready(unpack_ready),
    .sample_valid(unpack_sv), .sample(unpack_s));

  generate
    if (USE_SRAM) begin : g_sram
      sram_reader u_sram (
        .clk(clk), .rst_n(rst_n), .run(sram_run), .pace_en(sram_pace_en),
        .pace_inc(sram_pace_inc), .sample_total(sram_sample_total),
        .sram_rd(sram_rd), .sram_addr(sram_addr), .sram_rdata(sram_rdata),
        .sram_rvalid(sram_rvalid), .sample_valid(sram_sv), .sample(sram_s),
        .sample_count(), .done(sram_done));
      assign sample_valid = sram_sv;
      assign sample       = sram_s;
      assign byte_ready   = 1'b0;
    end else begin : g_file
      assign sample_valid = unpack_sv;
      assign sample       = unpack_s;
      assign byte_ready   = unpack_ready;
      assign sram_rd      = 1'b0;
      assign sram_addr    = '0;
      assign sram_done    = 1'b0;
    end
  endgenerate

  logic [31:0] sample_index, sample_count, tb_ms_count;
  logic        ms_tick, epoch_boundary_1s;

  sample_timebase u_tb (
    .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid),
    .sample_index(sample_index), .sample_count(sample_count),
    .sample_cnt_in_ms(), .ms_boundary(), .ms_tick(ms_tick),
    .bit_boundary(), .subframe_boundary(), .epoch_boundary(epoch_boundary_1s),
    .ms_in_bit(), .ms_count(tb_ms_count));

  logic file_done;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) file_done <= 1'b0;
    else if (cfg_valid && cfg_addr == 8'h00 && cfg_wdata[0]) file_done <= 1'b0;
    else if (!USE_SRAM && !run && sample_count != 32'd0) file_done <= 1'b1;
  end
  assign input_done = USE_SRAM ? sram_done : file_done;

  // 可编程历元：每 epoch_ms 个 1 ms 边界
  logic [31:0] ep_div, epoch_id;
  logic        epoch_pulse;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ep_div <= '0; epoch_id <= '0; epoch_pulse <= 1'b0;
    end else begin
      epoch_pulse <= 1'b0;
      if (ms_tick) begin
        if (ep_div + 32'd1 >= epoch_ms) begin
          ep_div      <= '0;
          epoch_id    <= epoch_id + 32'd1;
          epoch_pulse <= 1'b1;
        end else begin
          ep_div <= ep_div + 32'd1;
        end
      end
    end
  end

  // ---------------------------------------------------------------- 码发生器 + 写口分配
  logic        gen_start, gen_done, gen_busy, gen_bad, gen_to_acq;
  logic [5:0]  gen_prn;
  logic [3:0]  gen_ch;
  logic        gen_we;
  logic [10:0] gen_addr;
  logic        gen_chip;

  prn_code_gen u_prn (
    .clk(clk), .rst_n(rst_n), .start(gen_start), .prn(gen_prn),
    .busy(gen_busy), .done(gen_done), .bad_prn(gen_bad),
    .out_we(gen_we), .out_addr(gen_addr), .out_chip(gen_chip));

  // ---------------------------------------------------------------- 捕获
  logic        acq_start, acq_abort, acq_ack, acq_busy, acq_done, acq_found, acq_ready;
  logic [47:0] ho_phase;
  logic signed [31:0] res_dop;
  logic [11:0] res_h;
  logic [27:0] res_peak, res_mean;
  logic [5:0]  acq_prn;

  acquisition #(.N_LANES(N_LANES), .BUF_DEPTH(BUF_DEPTH)) u_acq (
    .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid), .sample(sample),
    .code_we(gen_we && gen_to_acq), .code_waddr(gen_addr), .code_wdata(gen_chip),
    .start(acq_start), .abort(acq_abort), .ack(acq_ack),
    .dop_min(dop_min), .dop_step(dop_step), .n_bins(n_bins), .nc(nc), .thr(thr),
    .busy(acq_busy), .done(acq_done), .found(acq_found), .ready(acq_ready),
    .ho_phase(ho_phase), .res_dop(res_dop), .res_h(res_h),
    .res_peak(res_peak), .res_mean(res_mean));

  // ---------------------------------------------------------------- 通道管理
  logic [N_CHANNELS-1:0] ch_enable, ch_init_load, ch_clear;
  logic [N_CHANNELS-1:0][PRN_W-1:0] ch_prn;
  logic [N_CHANNELS-1:0][2:0] ch_state;
  logic [N_CHANNELS-1:0][7:0] ch_gen;
  logic        ev_valid, ev_ready;
  logic        force_pend;
  logic [3:0]  ev_code, ev_ch;
  logic [5:0]  ev_prn;
  logic [7:0]  ev_gen;
  logic [31:0] ev_a1;
  logic [N_CHANNELS-1:0] dump_valid, dump_partial, bit_synced, sf_valid, sf_err;
  logic [N_CHANNELS-1:0] frame_synced, anchor_valid, week_valid, bit_val;

  channel_manager u_mgr (
    .clk(clk), .rst_n(rst_n), .run(run), .ms_tick(ms_tick),
    .n_prns(n_prns), .prn_list(prn_list), .pullin_to(pullin_to), .lost_to(lost_to),
    .bit_sync_to(bit_sync_to), .frame_sync_to(frame_sync_to),
    .acq_start(acq_start), .acq_abort(acq_abort), .acq_ack(acq_ack),
    .acq_busy(acq_busy), .acq_done(acq_done), .acq_found(acq_found), .acq_ready(acq_ready),
    .acq_prn(acq_prn),
    .gen_start(gen_start), .gen_prn(gen_prn), .gen_done(gen_done),
    .gen_busy(gen_busy), .gen_bad(gen_bad), .gen_to_acq(gen_to_acq), .gen_ch(gen_ch),
    .force_alloc(force_alloc), .force_ch(force_ch), .force_prn(force_prn),
    .ch_locked(ch_locked), .ch_bit_synced(bit_synced), .ch_frame_synced(frame_synced),
    .ch_enable(ch_enable), .ch_init_load(ch_init_load),
    .ch_clear(ch_clear), .ch_prn(ch_prn), .ch_state(ch_state), .ch_gen(ch_gen),
    .ev_valid(ev_valid), .ev_ready(ev_ready), .ev_code(ev_code), .ev_ch(ev_ch),
    .ev_prn(ev_prn), .ev_gen(ev_gen), .ev_a1(ev_a1));

  // ---------------------------------------------------------------- 12 通道
  logic [N_CHANNELS-1:0][31:0] dump_ms, code_phase, ms_count, bit_ms, sf_start_ms, anchor_ms;
  logic [N_CHANNELS-1:0][31:0] dop_word;
  logic [N_CHANNELS-1:0][3:0]  lock_cnt;
  logic [N_CHANNELS-1:0][2:0]  sf_id;
  logic [N_CHANNELS-1:0][19:0] sf_sow, anchor_sow;
  logic [N_CHANNELS-1:0][223:0] sf_info;
  logic [N_CHANNELS-1:0][4:0]  sf_fixes;
  logic [N_CHANNELS-1:0]       sf_inverted;
  logic [N_CHANNELS-1:0][12:0] week;
  logic signed [CORR_ACC_W-1:0] i_p [N_CHANNELS];

  assign ch_bit_valid = bit_synced;
  assign ch_nav_valid = frame_synced;

  genvar gi;
  generate
    for (gi = 0; gi < N_CHANNELS; gi++) begin : g_ch
      logic signed [CORR_ACC_W-1:0] ie, qe, ip, qp, il, ql;
      channel_slice u_ch (
        .clk(clk), .rst_n(rst_n), .enable(ch_enable[gi]),
        .sample_valid(sample_valid), .sample(sample),
        .code_we(gen_we && !gen_to_acq && (gen_ch == 4'(gi))),
        .code_waddr(gen_addr), .code_wdata(gen_chip),
        .init_load(ch_init_load[gi]), .clear(ch_clear[gi]),
        .init_carrier_phase(32'd0),
        .init_code_phase(force_pend ? force_phase : ho_phase),
        .init_doppler(force_pend ? force_dop : res_dop),
        .code_spacing(4'(CODE_SPACING_DEFAULT)), .fll_en(1'b1),
        .pll_kp(16'(PLL_KP_DEFAULT)), .pll_ki(16'(PLL_KI_DEFAULT)),
        .fll_k(16'(FLL_K_DEFAULT)), .dll_kp(16'(DLL_KP_DEFAULT)), .dll_ki(16'(DLL_KI_DEFAULT)),
        .dump_valid(dump_valid[gi]), .dump_partial(dump_partial[gi]), .dump_ms(dump_ms[gi]),
        .i_e(ie), .q_e(qe), .i_p(ip), .q_p(qp), .i_l(il), .q_l(ql),
        .code_phase(code_phase[gi]), .ms_count(ms_count[gi]), .epoch_tick(),
        .freq_word(), .dop_word(dop_word[gi]), .locked(ch_locked[gi]), .lock_cnt(lock_cnt[gi]),
        .bit_synced(bit_synced[gi]), .bit_valid(), .bit_val(bit_val[gi]), .bit_ms(bit_ms[gi]),
        .sf_valid(sf_valid[gi]), .sf_id(sf_id[gi]), .sf_sow(sf_sow[gi]),
        .sf_start_ms(sf_start_ms[gi]), .sf_info(sf_info[gi]), .sf_fixes(sf_fixes[gi]),
        .sf_inverted(sf_inverted[gi]), .frame_synced(frame_synced[gi]),
        .anchor_valid(anchor_valid[gi]), .anchor_ms(anchor_ms[gi]),
        .anchor_sow(anchor_sow[gi]), .week(week[gi]), .week_valid(week_valid[gi]),
        .sf_err(sf_err[gi]));
      assign i_p[gi] = ip;
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) force_pend <= 1'b0;
    else if (force_alloc) force_pend <= 1'b1;
    else if (|ch_init_load) force_pend <= 1'b0;
  end

  // ---------------------------------------------------------------- 测量 / 历元
  logic [N_CHANNELS-1:0][255:0] meas_rec;
  logic [11:0] n_valid;
  logic [255:0] epoch_rec;

  measurement_engine u_meas (
    .clk(clk), .rst_n(rst_n), .epoch_pulse(epoch_pulse), .epoch_id(epoch_id),
    .sample_count(sample_count),
    .dump_valid(dump_valid), .dump_partial(dump_partial), .dump_ms(dump_ms),
    .code_phase(code_phase), .dop_word(dop_word), .locked(ch_locked),
    .lock_cnt(lock_cnt), .bit_synced(bit_synced), .anchor_valid(anchor_valid),
    .anchor_ms(anchor_ms), .anchor_sow(anchor_sow), .week(week), .week_valid(week_valid),
    .ch_state(ch_state), .prn(ch_prn), .generation(ch_gen),
    .meas_rec(meas_rec), .n_valid(n_valid));

  epoch_aggregator u_ep (
    .clk(clk), .rst_n(rst_n), .epoch_pulse(epoch_pulse),
    .epoch_id(epoch_id), .sample_count(sample_count), .n_valid(n_valid),
    .input_done(input_done), .sow0_ms(sow0_ms), .epoch_rec(epoch_rec));

  // ---------------------------------------------------------------- 记录调度
  logic        fifo_wr_valid, fifo_wr_ready, fifo_ov;
  logic [255:0] fifo_wr_data;
  logic [5:0]  fifo_cnt;
  logic        ep_pend;
  logic [1:0]  ep_wait;
  logic [3:0]  meas_idx;
  logic [N_CHANNELS-1:0] nav_pend, par_pend;
  logic [3:0]  nav_sel, par_sel;

  record_fifo #(.DEPTH(32)) u_fifo (
    .clk(clk), .rst_n(rst_n),
    .wr_valid(fifo_wr_valid && fifo_wr_ready), .wr_ready(fifo_wr_ready),
    .wr_data(fifo_wr_data),
    .rd_valid(rec_valid), .rd_ready(rec_ready), .rd_data(rec_data),
    .overflow(fifo_ov), .count(fifo_cnt));

  integer ni;
  always_comb begin
    nav_sel = 4'd15;
    for (ni = N_CHANNELS - 1; ni >= 0; ni--)
      if (nav_pend[ni]) nav_sel = 4'(ni);
    par_sel = 4'd15;
    for (ni = N_CHANNELS - 1; ni >= 0; ni--)
      if (par_pend[ni]) par_sel = 4'(ni);
  end

  typedef enum logic [2:0] { RS_IDLE, RS_EPOCH, RS_MEAS } rs_t;
  rs_t rs;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rs <= RS_IDLE; ep_pend <= 1'b0; ep_wait <= '0; meas_idx <= '0;
      nav_pend <= '0; par_pend <= '0;
      fifo_wr_valid <= 1'b0; fifo_wr_data <= '0;
    end else begin
      if (epoch_pulse) ep_wait <= 2'd2;
      else if (ep_wait != 2'd0) begin
        ep_wait <= ep_wait - 2'd1;
        if (ep_wait == 2'd1) ep_pend <= 1'b1;
      end
      for (int i = 0; i < N_CHANNELS; i++) begin
        if (sf_valid[i]) nav_pend[i] <= 1'b1;
        if (sf_err[i])   par_pend[i] <= 1'b1;
      end

      fifo_wr_valid <= 1'b0;
      if (fifo_wr_ready) begin
        // 历元包连续：EPOCH + 12×MEAS 中途不插 STATUS/NAV
        if (rs == RS_MEAS) begin
          fifo_wr_valid <= 1'b1;
          fifo_wr_data  <= meas_rec[meas_idx];
          if (meas_idx == 4'(N_CHANNELS - 1)) rs <= RS_IDLE;
          else meas_idx <= meas_idx + 4'd1;
        end else if (rs == RS_IDLE && ep_pend) begin
          fifo_wr_valid <= 1'b1;
          fifo_wr_data  <= epoch_rec;
          ep_pend       <= 1'b0;
          meas_idx      <= 4'd0;
          rs            <= RS_MEAS;
        end else if (ep_wait == 2'd0 && ev_valid) begin
          fifo_wr_valid <= 1'b1;
          fifo_wr_data  <= pack_status(ev_ch, ev_prn, ev_gen, sample_count,
                                       ev_code, ev_a1, 32'd0, 12'd0);
        end else if (par_sel != 4'd15) begin
          fifo_wr_valid <= 1'b1;
          fifo_wr_data  <= pack_status(par_sel, ch_prn[par_sel], ch_gen[par_sel],
                                       sample_count, EV_NAV_PARITY, 32'd0, 32'd0, 12'd0);
          par_pend[par_sel] <= 1'b0;
        end else if (nav_sel != 4'd15) begin
          fifo_wr_valid <= 1'b1;
          fifo_wr_data  <= pack_nav(nav_sel, ch_prn[nav_sel], ch_gen[nav_sel][3:0],
                                    sf_id[nav_sel], sf_fixes[nav_sel],
                                    sf_inverted[nav_sel], sf_info[nav_sel]);
          nav_pend[nav_sel] <= 1'b0;
        end
      end
    end
  end

  assign ev_ready = fifo_wr_ready && ev_valid && (rs == RS_IDLE)
                    && !ep_pend && (ep_wait == 2'd0);

  assign error_valid = fifo_ov;
  assign error_code  = fifo_ov ? ERR_FIFO_OVERFLOW : 32'd0;

endmodule
