`include "b1i_params.svh"
module tb_nh_clear;
  logic clk=0, rst_n=0, clear=0, synced, bit_valid;
  always #5 clk=~clk;
  logic [63:0] bit_end_sample;
  logic [47:0] bit_end_phase;
  nh_bit_sync dut (
    .clk(clk),.rst_n(rst_n),.clear(clear),.dump_valid(1'b0),.dump_partial(1'b0),
    .dump_ms(32'd0),.dump_sample_count(64'd123456),.dump_code_phase(48'd123456),.i_p(26'sd0),
    .synced(synced),.bit_phase(),.bit_valid(bit_valid),.bit_val(),.bit_ms(),.bit_mag(),
    .bit_end_sample(bit_end_sample),.bit_end_phase(bit_end_phase));
  initial begin
    repeat(3) @(negedge clk); rst_n=1;
    // Old channel is one cycle from declaring phase lock.
    force dut.di=5'd20; force dut.best_v=40'd1000; force dut.second_v=40'd10;
    @(negedge clk); release dut.di; release dut.best_v; release dut.second_v;
    clear=1; @(negedge clk); clear=0;
    repeat(30) begin
      @(negedge clk);
      if (synced || bit_valid || dut.best_v!=0 || dut.di!=0) $fatal(1,"old NH decision committed after clear");
    end
    // Cancel an in-flight bit computation and its measured metadata too.
    force dut.synced=1'b1; force dut.run=1'b1; force dut.k=5'd19;
    force dut.sample_tag=64'd123456; force dut.phase_tag=48'd123456;
    @(negedge clk);
    release dut.synced; release dut.run; release dut.k; release dut.sample_tag; release dut.phase_tag;
    clear=1; @(negedge clk); clear=0;
    repeat(30) begin
      @(negedge clk);
      if (synced || bit_valid || bit_end_sample!=0 || bit_end_phase!=0 || dut.run)
        $fatal(1,"old NH bit or metadata survived clear");
    end
    $display("TEST PASSED"); $finish;
  end
endmodule
