`timescale 1ns/1ps
`include "b1i_params.svh"
// Directed state injection isolates handover arithmetic from the full search.
// This test is not evidence of acquisition sensitivity or six-satellite decoding.
module tb_handover;
  logic clk=0, rst_n=0, valid=0;
  always #5 clk=~clk;
  logic ready, done, found, pause_if;
  logic [47:0] phase;
  logic [31:0] carrier;
  bds_acquisition #(.N_LANES(4),.BUF_DEPTH(256)) dut (
    .clk(clk),.rst_n(rst_n),.sample_valid(valid),.sample(3'sd1),
    .code_we(1'b0),.code_waddr(11'd0),.code_wdata(1'b0),
    .start(1'b0),.abort(1'b0),.ack(1'b0),.dop_min(32'sd0),.dop_step(32'sd0),
    .n_bins(8'd1),.nc(2'd1),.thr(8'd56),.busy(),.done(done),.found(found),.ready(ready),
    .input_pause(pause_if),.ho_phase(phase),.ho_carrier(carrier),
    .res_dop(),.res_h(),.res_peak(),.res_mean());
  logic [47:0] ref_phase, start_phase, step;
  logic [31:0] ref_carrier;
  logic signed [31:0] dop;
  longint unsigned expected;
  integer accepted, loops;

  task automatic run_case(input integer backlog, input integer sparse,
                          input logic signed [31:0] frequency);
    rst_n=0; valid=0;
    repeat(3) @(negedge clk); rst_n=1;
    dop=frequency;
    step=CODE_NCO_INC_NOMINAL+48'((45'(dop)*45'sd2749) >>> CODE_AID_SHIFT);
    start_phase=CODE_NCO_PERIOD-48'd100;
    // Deposit at a falling edge: no cycle executes while state is seeded.
    dut.st=dut.S_CATCHUP; dut.pend=backlog; dut.nco_run=start_phase;
    dut.inc_ho=step; dut.ho_carrier=32'hfffffff0; dut.res_dop=dop;
    accepted=0; loops=0;
    while(!ready && loops<backlog+10) begin
      valid=(sparse==0 || loops%3!=0);
      @(posedge clk); if(valid) accepted++;
      @(negedge clk); loops++;
      if(pause_if) $fatal(1,"IF was paused");
    end
    if(!ready || !found || !done) $fatal(1,"catchup did not finish");
    expected=(64'(start_phase)+64'(backlog+accepted)*64'(step))%64'(CODE_NCO_PERIOD);
    ref_carrier=32'hfffffff0+32'((backlog+accepted)*(FREQ_WORD_IF+dop));
    if(phase!==48'(expected) || carrier!==ref_carrier)
      $fatal(1,"handover phase mismatch got %h/%h expected %h/%h",phase,carrier,expected,ref_carrier);
    repeat(8) begin
      valid=1;
      expected=(expected+step)%64'(CODE_NCO_PERIOD);
      ref_carrier=ref_carrier+FREQ_WORD_IF+dop;
      @(negedge clk);
      if(phase!==48'(expected) || carrier!==ref_carrier || done)
        $fatal(1,"ready phase did not follow continuous IF");
    end
    $display("HANDOVER PASS backlog=%0d sparse=%0d dop=%0d cycles=%0d",backlog,sparse,dop,loops);
  endtask
  initial begin
    run_case(0,0,0); run_case(1,0,131200); run_case(5,0,-131200);
    run_case(37,0,1300000); run_case(9,1,-1300000);
    $display("TEST PASSED"); $finish;
  end
  initial begin #100000; $fatal(1,"handover timeout"); end
endmodule
