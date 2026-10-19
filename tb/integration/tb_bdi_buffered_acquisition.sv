`timescale 1ns/1ps
// Exercise the ORIGINAL parallel acquisition engine with signed source zeros.
module tb_bdi_buffered_acquisition;
  logic clk=0,rst_n=0,start=0,gen_start=0,feed=0;
  wire signed [1:0] if_sample;
  wire valid,code_we,code_bit,gen_done,found,done,ready,input_pause;
  wire [10:0] code_addr;
  wire [11:0] phase_halfchips;
  wire [27:0] peak,mean;
  wire signed [31:0] doppler;
  integer samples=0;
  always #1 clk=~clk;
  bdi_signal_source source(.clk_16m368(clk),.rst_n(rst_n),.enable(feed && !input_pause),
    .if_sample(if_sample),.if_valid(valid),.dbg_nav_bit(),.dbg_nh_bit(),.dbg_prn_bit(),
    .dbg_prn_phase(),.dbg_nh_idx(),.dbg_nav_idx());
  prn_code_gen gen(.clk(clk),.rst_n(rst_n),.start(gen_start),.prn(6'd6),.busy(),.done(gen_done),
    .bad_prn(),.out_we(code_we),.out_addr(code_addr),.out_chip(code_bit));
  acquisition #(.BUF_DEPTH(16620)) dut (
    .clk(clk),.rst_n(rst_n),.sample_valid(valid),.sample({if_sample[1],if_sample}),
    .code_we(code_we),.code_waddr(code_addr),.code_wdata(code_bit),
    .start(start),.abort(1'b0),.ack(1'b0),.dop_min(32'sd0),.dop_step(32'sd0),
    .n_bins(8'd1),.nc(2'd1),.thr(8'd40),.busy(),.done(done),.found(found),
    .ready(ready),.input_pause(input_pause),.ho_phase(),.res_dop(doppler),
    .res_h(phase_halfchips),.res_peak(peak),.res_mean(mean));
  always @(posedge clk) if(rst_n && valid) samples=samples+1;
  initial begin
    repeat(5) @(negedge clk);rst_n=1;
    @(negedge clk);gen_start=1;
    @(negedge clk);gen_start=0;
    wait(gen_done);
    @(negedge clk);start=1;
    @(negedge clk);start=0;feed=1;
    wait(done);@(negedge clk);
    if(!found || !ready || phase_halfchips!=20 || doppler!=0 || peak==0)
      $fatal(1,"parallel engine/source mismatch: found=%0d h=%0d dop=%0d peak=%0d mean=%0d",found,phase_halfchips,doppler,peak,mean);
    $display("BDI PARALLEL found=%0d h=%0d dop=%0d peak=%0d mean=%0d samples=%0d",found,phase_halfchips,doppler,peak,mean,samples);
    $display("TEST PASSED: original 64-lane engine acquired the real signed teacher source");
    $finish;
  end
  initial begin #20000000;$fatal(1,"parallel BDI acquisition timeout");end
endmodule
