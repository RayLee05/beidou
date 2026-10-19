`timescale 1ns/1ps
module tb_acq_sample_storage;
  logic clk=0, rst_n=0, start=0, abort=0, valid=0;
  logic signed [2:0] sample;
  localparam integer DEPTH=16620;
  always #1 clk=~clk;
  acquisition #(.BUF_DEPTH(DEPTH)) dut (
    .clk(clk), .rst_n(rst_n), .sample_valid(valid), .sample(sample),
    .code_we(1'b0), .code_waddr(11'd0), .code_wdata(1'b0),
    .start(start), .abort(abort), .ack(1'b0), .dop_min(32'sd0),
    .dop_step(32'sd0), .n_bins(8'd1), .nc(2'd1), .thr(8'd40),
    .busy(), .done(), .found(), .ready(), .input_pause(), .ho_phase(),
    .res_dop(), .res_h(), .res_peak(), .res_mean());
  integer compared=0;
  always @(posedge clk) if (rst_n && dut.pv) begin
    if ($signed(dut.u_mix.sample) !== $signed(3'(dut.kd % 8)))
      $fatal(1,"Replay lost signed sample at %0d: got %0d expected %0d",dut.kd,$signed(dut.u_mix.sample),$signed(3'(dut.kd%8)));
    compared=compared+1;
  end
  initial begin
    repeat(4) @(negedge clk); rst_n=1;
    @(negedge clk); start=1;
    @(negedge clk); start=0;
    for(integer i=0;i<DEPTH;i++) begin
      valid=1; sample=3'(i%8); @(negedge clk);
    end
    valid=0;
    wait(compared>=64);
    @(negedge clk); abort=1;
    @(negedge clk); abort=0;
    $display("TEST PASSED: all eight signed 3-bit levels, including zero, survive capture/replay");
    $finish;
  end
  initial begin #1000000; $fatal(1,"storage test timeout"); end
endmodule
