// tb_channel_manager.sv -- 强制装载与捕获命中移交
`include "b1i_params.svh"
`include "b1i_records.svh"

module tb_channel_manager;

  logic clk = 1'b0, rst_n, run, ms_tick;
  always #5 clk = ~clk;

  logic [3:0] n_prns;
  logic [11:0][5:0] prn_list;
  logic [31:0] pullin_to, lost_to;

  logic acq_start, acq_abort, acq_ack, acq_busy, acq_done, acq_found, acq_ready;
  logic [5:0] acq_prn;
  logic gen_start, gen_done, gen_busy, gen_bad, gen_to_acq;
  logic [5:0] gen_prn;
  logic [3:0] gen_ch;
  logic force_alloc;
  logic [3:0] force_ch;
  logic [5:0] force_prn;
  logic [11:0] ch_locked, ch_enable, ch_init_load, ch_clear;
  logic [11:0][5:0] ch_prn;
  logic [11:0][2:0] ch_state;
  logic [11:0][7:0] ch_gen;
  logic ev_valid, ev_ready;
  logic [3:0] ev_code, ev_ch;
  logic [5:0] ev_prn;
  logic [7:0] ev_gen;
  logic [31:0] ev_a1;

  channel_manager dut (
    .clk(clk), .rst_n(rst_n), .run(run), .ms_tick(ms_tick),
    .n_prns(n_prns), .prn_list(prn_list), .pullin_to(pullin_to), .lost_to(lost_to),
    .bit_sync_to(32'd100000), .frame_sync_to(32'd100000),
    .acq_start(acq_start), .acq_abort(acq_abort), .acq_ack(acq_ack),
    .acq_busy(acq_busy), .acq_done(acq_done), .acq_found(acq_found), .acq_ready(acq_ready),
    .acq_prn(acq_prn),
    .gen_start(gen_start), .gen_prn(gen_prn), .gen_done(gen_done),
    .gen_busy(gen_busy), .gen_bad(gen_bad), .gen_to_acq(gen_to_acq), .gen_ch(gen_ch),
    .force_alloc(force_alloc), .force_ch(force_ch), .force_prn(force_prn),
    .ch_locked(ch_locked), .ch_bit_synced(12'd0), .ch_frame_synced(12'd0),
    .ch_enable(ch_enable), .ch_init_load(ch_init_load),
    .ch_clear(ch_clear), .ch_prn(ch_prn), .ch_state(ch_state), .ch_gen(ch_gen),
    .ev_valid(ev_valid), .ev_ready(ev_ready), .ev_code(ev_code), .ev_ch(ev_ch),
    .ev_prn(ev_prn), .ev_gen(ev_gen), .ev_a1(ev_a1));

  // 假码发生器：start 后 4 拍 done
  integer gen_cnt;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      gen_busy <= 0; gen_done <= 0; gen_bad <= 0; gen_cnt <= 0;
    end else begin
      gen_done <= 0;
      if (gen_start) begin gen_busy <= 1; gen_cnt <= 4; end
      else if (gen_busy) begin
        if (gen_cnt == 1) begin gen_busy <= 0; gen_done <= 1; end
        gen_cnt <= gen_cnt - 1;
      end
    end
  end

  // 假捕获：start 后 6 拍 done+found+ready
  integer acq_cnt;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acq_busy <= 0; acq_done <= 0; acq_found <= 0; acq_ready <= 0; acq_cnt <= 0;
    end else begin
      acq_done <= 0;
      if (acq_ack) begin acq_busy <= 0; acq_found <= 0; acq_ready <= 0; end
      else if (acq_start) begin acq_busy <= 1; acq_cnt <= 6; end
      else if (acq_busy && acq_cnt != 0) begin
        if (acq_cnt == 1) begin
          acq_done <= 1; acq_found <= 1; acq_ready <= 1;
        end
        acq_cnt <= acq_cnt - 1;
      end
    end
  end

  integer errors = 0, cycles;

  initial begin
    rst_n = 0; run = 0; ms_tick = 0; n_prns = 1; prn_list = '0;
    prn_list[0] = 6'd7; pullin_to = 32'd100; lost_to = 32'd100;
    ch_locked = '0; force_alloc = 0; force_ch = 0; force_prn = 6'd3;
    ev_ready = 1;
    repeat (3) @(negedge clk);
    rst_n = 1;
    @(negedge clk);

    // 1) 强制装载 PRN 3 → CH0
    run = 1;
    force_alloc = 1; force_ch = 0; force_prn = 6'd3;
    @(negedge clk);
    force_alloc = 0;
    cycles = 0;
    while (!ch_enable[0] && cycles < 40) begin
      @(negedge clk); cycles++;
    end
    if (!ch_enable[0] || ch_prn[0] != 6'd3 || ch_state[0] != CH_PULLIN) begin
      $display("FAIL force: en=%b prn=%0d st=%0d", ch_enable[0], ch_prn[0], ch_state[0]);
      errors++;
    end

    // 2) 捕获命中 → 应分配 CH1（CH0 已占用）
    n_prns = 1;
    cycles = 0;
    while (!ch_enable[1] && cycles < 80) begin
      @(negedge clk); cycles++;
    end
    if (!ch_enable[1] || ch_prn[1] != 6'd7) begin
      $display("FAIL acq handoff: en1=%b prn1=%0d", ch_enable[1], ch_prn[1]);
      errors++;
    end
    if (!acq_ack) begin
      // ack 是单拍，可能已过；看通道状态即可
    end

    // 3) 两通道同拍锁定：事件不得互相覆盖
    ev_ready = 0;
    ch_locked[0] = 1; ch_locked[1] = 1;
    @(negedge clk);
    ms_tick = 1;
    @(negedge clk);
    ms_tick = 0;
    repeat (2) @(negedge clk);
    ev_ready = 1;
    begin : drain_lock
      integer n_lock, k;
      n_lock = 0;
      for (k = 0; k < 12; k++) begin
        @(posedge clk);
        if (ev_valid && ev_code == EV_LOCKED) n_lock++;
      end
      if (n_lock < 2) begin
        $display("FAIL multi-event: LOCKED count=%0d", n_lock);
        errors++;
      end
    end

    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d", errors);
    $finish;
  end

  initial begin
    #20000;
    $display("FAIL: timeout");
    $finish;
  end

endmodule
