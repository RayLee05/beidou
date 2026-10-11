`include "b1i_params.svh"
// Seed the global counters just before 1 s, then process real direct samples.
// This checks top-level snapshot timing without simulating the preceding 1 s.
module tb_public_epoch;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;
  logic direct_valid=0, direct_last=0, direct_ready;
  logic signed [2:0] direct_sample=1;
  logic cfg_valid=0;
  logic [7:0] cfg_addr=0;
  logic [31:0] cfg_wdata=0;
  logic rec_valid, rec_ready=0, error_valid;
  logic [255:0] rec_data;
  logic [11:0] ch_locked;
  integer cycles=0, received=0, commons=0, tracks=0, ends=0;
  localparam logic [47:0] PHASE0 = CODE_NCO_PERIOD - 2*CODE_NCO_INC_NOMINAL;
  localparam logic [63:0] BASE = 64'd16368000-64'd16;
  b1i_rx_top #(.N_LANES(4), .BUF_DEPTH(256), .DIRECT_SAMPLES(1'b1), .PUBLIC_RECORDS(1'b1)) dut (
    .clk(clk), .rst_n(rst_n), .byte_valid(1'b0), .data_byte(8'd0), .byte_ready(),
    .direct_valid(direct_valid), .direct_sample(direct_sample), .direct_last(direct_last),
    .direct_input_error(1'b0), .direct_missing_ticks(64'd0), .direct_ready(direct_ready),
    .sram_run(1'b0), .sram_pace_en(1'b0), .sram_pace_inc(32'd0), .sram_sample_total(32'd0),
    .sram_rd(), .sram_addr(), .sram_rdata(8'd0), .sram_rvalid(1'b0), .sram_done(),
    .cfg_valid(cfg_valid), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata), .cfg_ready(), .cfg_rdata(),
    .rec_valid(rec_valid), .rec_ready(rec_ready), .rec_data(rec_data), .rec_last(),
    .ch_locked(ch_locked), .ch_bit_valid(), .ch_nav_valid(), .error_valid(error_valid), .error_code());
  always @(negedge clk) begin cycles++; rec_ready=(cycles%13<6); end
  always @(posedge clk) if (rst_n && dut.ch_init_load[0] && direct_ready)
    $fatal(1,"sample would be consumed during channel NCO load");
  always @(posedge clk) if (rst_n && rec_valid && rec_ready) begin
    if (ends) $fatal(1,"record after END");
    received++;
    if (rec_data[13:8]!=39 && rec_data[7:0]!=6) $fatal(1,"PRN identity");
    case (rec_data[7:0])
      4: begin
        commons++;
        if (rec_data[95:32]!=16368000 || rec_data[127:96]!=1 || rec_data[159:144]!=1
            || rec_data[170:160]!=1 || rec_data[202:171]!=32'hc0000000 || rec_data[22])
          $fatal(1,"common snapshot not at accepted boundary sample");
      end
      1: begin
        tracks++;
        if (rec_data[95:32]!=16368000+SAMPLES_PER_MS-14 || rec_data[255:243]!=2
            || rec_data[242:232]!=0 || rec_data[231:208]!=0 || rec_data[207:176]!=32'h80000000)
          $fatal(1,"dump timestamp/NCO state delayed by a sample");
      end
      6: begin
        ends++;
        if (rec_data[95:32]!=16368000+SAMPLES_PER_MS || rec_data[19:18]!=0)
          $fatal(1,"END count");
      end
      default: $fatal(1,"unexpected record");
    endcase
  end
  task automatic config_write(input logic [7:0] a,input logic [31:0] d);
    @(negedge clk); cfg_valid=1; cfg_addr=a; cfg_wdata=d;
    @(negedge clk); cfg_valid=0;
  endtask
  initial begin
    repeat(3) @(negedge clk); rst_n=1;
    config_write(8'h00,32'd1);
    config_write(8'h21,PHASE0[31:0]); config_write(8'h22,{16'd0,PHASE0[47:32]});
    config_write(8'h23,32'd0); config_write(8'h20,(32'd39<<8)|32'd1);
    wait(dut.ch_init_load[0]); repeat(3) @(negedge clk);
    force dut.accepted_samples=BASE;
    force dut.u_tb.sample_count=32'(BASE); force dut.u_tb.sample_index=32'(BASE);
    force dut.u_tb.sample_cnt_in_ms=14'(SAMPLES_PER_MS-16); force dut.u_tb.ms_count=999;
    force dut.ep_div=999;
    @(negedge clk);
    release dut.accepted_samples; release dut.u_tb.sample_count; release dut.u_tb.sample_index;
    release dut.u_tb.sample_cnt_in_ms; release dut.u_tb.ms_count; release dut.ep_div;
    for (int n=0; n<SAMPLES_PER_MS+16; n++) begin
      @(negedge clk); direct_valid=1; direct_last=(n==SAMPLES_PER_MS+15);
      direct_sample=(n%2==0 ? 3'sd1 : -3'sd3);
      do @(posedge clk); while(!direct_ready);
      @(negedge clk); direct_valid=0;
      if (n%11==0) repeat(2) @(negedge clk);
    end
    wait(ends==1); repeat(10) @(negedge clk);
    if (commons!=1 || tracks!=1 || received!=3 || error_valid) $fatal(1,"record count/error");
    $display("TEST PASSED"); $finish;
  end
  initial begin #1000000; $fatal(1,"timeout"); end
endmodule
