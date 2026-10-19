`timescale 1ns/1ps
// This is the ONE testbench used at the teacher's demonstration.
// Source debug bits are used only for viewing/comparison, never by the receiver.
module tb_single_sat_capture;
  logic clk=0, reset_n=0, start=0, run_source=0;
  wire ready, if_valid;
  wire signed [1:0] if_sample;
  wire signal_code_raw;
  logic signal_code;
  wire local_code, code_same;
  wire [10:0] trying_phase, result_phase, captured_phase;
  wire [48:0] energy;
  wire capture, dump;
  wire signed [23:0] sum_a,sum_b;
  wire [31:0] window_id;
  integer accepted_samples=0, different_samples=0, file_id;
  string csv_path;

  // About 16.368 MHz, so the displayed window is about 1 ms.
  always #30.547410 clk=~clk;

  bdi_signal_source signal_source (
    .clk_16m368(clk),.rst_n(reset_n),.enable(ready && run_source),
    .if_sample(if_sample),.if_valid(if_valid),.dbg_prn_bit(signal_code_raw),
    .dbg_nav_bit(),.dbg_nh_bit(),.dbg_prn_phase(),.dbg_nh_idx(),.dbg_nav_idx());
  // The source registers its IF output; delay its displayed code by one clock.
  always @(posedge clk) signal_code <= signal_code_raw;
  assign code_same = (signal_code == local_code);

  bdi_sliding_correlator receiver (
    .clk(clk),.rst_n(reset_n),.start(start),.if_sample(if_sample),.if_valid(if_valid),
    .ready(ready),.bad_prn(),.capture(capture),.capture_phase(captured_phase),.dump(dump),
    .i_result(sum_a),.q_result(sum_b),.magnitude(),.energy(energy),
    .result_phase(result_phase),.candidate_phase(trying_phase),.result_window(window_id),
    .sample_in_window(),.local_index(),.local_prn_bit(local_code),
    .local_cos(),.local_sin(),.product_i(),.product_q(),.i_acc(),.q_acc());

  // Checks below are in the testbench and do not control the receiver decision.
  always @(posedge clk) if(reset_n && ready && if_valid) begin
    accepted_samples=accepted_samples+1;
    if(signal_code !== local_code) different_samples=different_samples+1;
  end
  always @(negedge clk) if(reset_n && dump) begin
    $fdisplay(file_id,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",window_id,result_phase,
      $signed(sum_a),$signed(sum_b),energy,capture,accepted_samples,different_samples);
    $display("Window %0d: phase=%0d energy=%0d capture=%0d different_samples=%0d",
      window_id,result_phase,energy,capture,different_samples);
    if(accepted_samples!=window_id*16368) $fatal(1,"incomplete integration window");
    if(window_id<11 && capture) $fatal(1,"early capture");
    if(window_id>=11 && (!capture || captured_phase!=10 || result_phase!=10 || different_samples!=0))
      $fatal(1,"code/phase/capture verification failed");
    different_samples=0;
    if(window_id==13) begin
      $fclose(file_id);
      $display("TEST PASSED: single satellite, capture at phase 10, two confirmation windows");
      $finish;
    end
  end
  initial begin
    if(!$value$plusargs("CSV=%s",csv_path)) csv_path="capture.csv";
    file_id=$fopen(csv_path,"w");
    if(!file_id) $fatal(1,"cannot open evidence CSV");
    $fdisplay(file_id,"window,phase,sum_a,sum_b,energy,capture,accepted_samples,different_samples");
    repeat(5) @(negedge clk); reset_n=1;
    @(negedge clk); start=1;
    @(negedge clk); start=0;
    wait(ready); @(negedge clk); run_source=1;
  end
  initial begin #20000000; $fatal(1,"single-satellite demo timeout"); end
endmodule
