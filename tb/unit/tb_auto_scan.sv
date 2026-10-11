`include "b1i_params.svh"
module tb_auto_scan;
  logic clk=0, rst_n=0, run=0, search_enable=1;
  always #5 clk=~clk;
  logic acq_start, acq_abort, acq_ack, acq_busy=0, acq_done=0, acq_found=0, acq_ready=0;
  logic [5:0] acq_prn, gen_prn;
  logic gen_start, gen_done=0, gen_busy=0, gen_to_acq;
  logic [3:0] gen_ch;
  logic [11:0] ch_enable, ch_init_load;
  logic [11:0][5:0] ch_prn;
  logic [11:0][7:0] ch_gen;
  integer gen_timer=0, acq_timer=0, searched=0;
  channel_manager #(.AUTO_SCAN(1'b1)) dut (
    .clk(clk), .rst_n(rst_n), .run(run), .search_enable(search_enable), .ms_tick(1'b0),
    .n_prns(4'd0), .prn_list(72'd0), .pullin_to(32'd10000), .lost_to(32'd10000),
    .bit_sync_to(32'd10000), .frame_sync_to(32'd10000),
    .acq_start(acq_start), .acq_abort(acq_abort), .acq_ack(acq_ack), .acq_busy(acq_busy),
    .acq_done(acq_done), .acq_found(acq_found), .acq_ready(acq_ready), .acq_prn(acq_prn),
    .gen_start(gen_start), .gen_prn(gen_prn), .gen_done(gen_done), .gen_busy(gen_busy),
    .gen_bad(1'b0), .gen_to_acq(gen_to_acq), .gen_ch(gen_ch),
    .force_alloc(1'b0), .force_ch(4'd0), .force_prn(6'd0), .force_handover(),
    .ch_locked(12'd0), .ch_bit_synced(12'd0), .ch_frame_synced(12'd0),
    .ch_enable(ch_enable), .ch_init_load(ch_init_load), .ch_clear(), .ch_prn(ch_prn),
    .ch_state(), .ch_gen(ch_gen), .ev_valid(), .ev_ready(1'b1),
    .ev_code(), .ev_ch(), .ev_prn(), .ev_gen(), .ev_a1());
  always @(posedge clk) if (rst_n) begin
    gen_done<=0; acq_done<=0;
    if (gen_start) begin gen_busy<=1; gen_timer<=2; end
    else if (gen_timer>0) begin
      gen_timer<=gen_timer-1;
      if (gen_timer==1) begin gen_busy<=0; gen_done<=1; end
    end
    if (acq_abort || acq_ack) begin acq_busy<=0; acq_ready<=0; acq_timer<=0; end
    else if (acq_start) begin
      // First traversal 1..63, then skip PRN 1 because it is allocated.
      if (searched<63 && acq_prn != 6'(searched+1)) $fatal(1,"incomplete scan at %0d",searched);
      if (searched==63 && acq_prn != 2) $fatal(1,"occupied PRN searched again");
      searched++; acq_busy<=1; acq_timer<=4;
    end else if (acq_timer>0) begin
      acq_timer<=acq_timer-1;
      if (acq_timer==1) begin
        acq_done<=1; acq_found<=(acq_prn==1); acq_ready<=(acq_prn==1);
        if (acq_prn!=1) acq_busy<=0;
      end
    end
  end
  initial begin
    repeat(3) @(negedge clk); rst_n=1; run=1;
    wait(searched==64); @(negedge clk); search_enable=0;
    repeat(10) @(negedge clk);
    if (searched!=64 || acq_busy || ch_enable!=12'd1 || ch_prn[0]!=1 || ch_gen[0]!=1)
      $fatal(1,"EOF search stop damaged allocated channel");
    search_enable=1;
    wait(searched==65);
    $display("TEST PASSED"); $finish;
  end
  initial begin #100000; $fatal(1,"scan timeout"); end
endmodule
