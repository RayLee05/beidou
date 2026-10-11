`include "b1i_params.svh"
// Continuous producer: catch-up must create a gap itself and drain its backlog.
// Seed only the post-search state; acquisition detection has its own system TB.
module tb_acq_input_pause;
  logic clk=0, rst_n=0, producer_valid=0, input_pause, sample_valid;
  always #5 clk=~clk;
  assign sample_valid=producer_valid && !input_pause;
  logic ready, done, found;
  logic [47:0] ho_phase;
  integer accepted=0, cycles=0;
  localparam logic [47:0] START_PHASE=48'd1000<<37;
  acquisition #(.N_LANES(4),.BUF_DEPTH(256)) dut (
    .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample(3'sd1),
    .code_we(1'b0),.code_waddr(11'd0),.code_wdata(1'b0),
    .start(1'b0),.abort(1'b0),.ack(1'b0),.dop_min(32'd0),.dop_step(32'd0),
    .n_bins(8'd1),.nc(2'd1),.thr(8'd40),.busy(),.done(done),.found(found),.ready(ready),
    .input_pause(input_pause),.ho_phase(ho_phase),.res_dop(),.res_h(),.res_peak(),.res_mean());
  always @(posedge clk) if (rst_n && sample_valid) accepted++;
  initial begin
    repeat(3) @(negedge clk); rst_n=1;
    force dut.st=dut.S_CATCHUP; force dut.pend=32'd5;
    force dut.nco_run=START_PHASE; force dut.inc_ho=CODE_NCO_INC_NOMINAL;
    @(negedge clk);
    release dut.st; release dut.pend; release dut.nco_run; release dut.inc_ho;
    // The seeded state executes once while forced; start the producer now.
    producer_valid=1;
    while(!ready && cycles<20) begin @(negedge clk); cycles++; end
    if (!ready || !done || !found || accepted!=0 || cycles>7
        || ho_phase!=START_PHASE+5*CODE_NCO_INC_NOMINAL || input_pause)
      $fatal(1,"continuous input prevented phase catch-up");
    @(negedge clk);
    if (accepted!=1 || ho_phase!=START_PHASE+6*CODE_NCO_INC_NOMINAL)
      $fatal(1,"input did not resume at the caught-up phase");
    $display("TEST PASSED"); $finish;
  end
endmodule
