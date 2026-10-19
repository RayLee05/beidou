`timescale 1ns/1ps
module tb_bdi_sliding_correlator;
  logic clk=0, rst_n=0, start=0, valid=0;
  logic signed [1:0] sample=0;
  wire ready, capture, dump;
  wire signed [23:0] ir,qr;
  wire [24:0] mag;
  wire [48:0] energy;
  wire [13:0] count;
  wire [31:0] window_id;
  wire [10:0] wrap_phase;
  always #1 clk=~clk;
  bdi_sliding_correlator #(.AUTO_STEP(1'b0),.ENERGY_THRESHOLD(49'd49)) dut (
    .clk(clk),.rst_n(rst_n),.start(start),.if_sample(sample),.if_valid(valid),
    .ready(ready),.bad_prn(),.capture(capture),.capture_phase(),.dump(dump),
    .i_result(ir),.q_result(qr),.magnitude(mag),.energy(energy),.result_phase(),.candidate_phase(),
    .result_window(window_id),.sample_in_window(count),.local_index(),.local_prn_bit(),
    .local_cos(),.local_sin(),.product_i(),.product_q(),.i_acc(),.q_acc());
  bdi_sliding_correlator #(.START_PHASE(2045)) wrap_search (
    .clk(clk),.rst_n(rst_n),.start(start),.if_sample(2'sd0),.if_valid(valid),
    .candidate_phase(wrap_phase));
  task automatic send(input logic signed [1:0] value,input logic active);
    @(negedge clk); sample=value; valid=active;
    @(posedge clk); #0.01;
  endtask
  task automatic begin_session;
    @(negedge clk); valid=0; start=1;
    @(negedge clk); start=0;
    wait(ready); @(negedge clk);
  endtask
  initial begin
    repeat(4) @(negedge clk); rst_n=1;
    begin_session();
    for(integer n=0;n<16368;n++) begin
      send(0,1);
      if(dump !== (n==16367)) $fatal(1,"incorrect first dump boundary");
    end
    if(mag!=0 || capture) $fatal(1,"zero input captured");
    if(wrap_phase!=0) $fatal(1,"candidate 2045 did not wrap to zero");
    send(0,0);
    if(dump) $fatal(1,"dump pulse exceeded one clock");
    for(integer n=0;n<16367;n++) send(0,1);
    for(integer n=0;n<7;n++) begin
      send(1,0);
      if(count!=16367 || dump || capture) $fatal(1,"invalid beat advanced state");
    end
    send(1,1);
    // PRN6 chip 2045 is 1; the final local cosine is +7.
    if(!dump || ir!=-7 || qr!=0 || mag!=7 || energy!=49 || !capture || window_id!=2)
      $fatal(1,"last-sample inclusion or inclusive threshold failed I=%0d Q=%0d M=%0d",ir,qr,mag);
    repeat(5) begin
      send(0,0);
      if(dump || !capture || ir!=-7) $fatal(1,"capture/result hold failed");
    end
    begin_session();
    if(capture || window_id!=0 || count!=0 || ir!=0 || qr!=0) $fatal(1,"restart retained state");
    repeat(12) send(1,1);
    @(negedge clk); valid=0; rst_n=0;
    #0.01;
    if(capture || ready || dump || count || dut.i_acc || dut.q_acc) $fatal(1,"reset failed");
    $display("TEST PASSED: zero input, final nonzero sample, >= threshold, invalid gaps, hold/restart/reset");
    $finish;
  end
  initial begin #1000000; $fatal(1,"BDI unit timeout"); end
endmodule
