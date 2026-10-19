`timescale 1ns/1ps
// The teacher source and package are compiled externally by run_bdi_capture.py.
// dbg_* is connected only to scoreboard/waveform signals, never to any DUT.
module tb_bdi_teacher_capture;
  import bdi_prn_code_pkg::*;
  logic clk=0, rst_n=0, start=0;
  logic run_source=0, pause_source=0;
  integer gap_period=0, cycle_count=0;
  wire ready, wrong_ready, fixed_ready, zero_ready;
  wire enable_source = run_source && ready && wrong_ready && fixed_ready && zero_ready && !pause_source;
  wire signed [1:0] if_sample;
  wire if_valid, tx_bit_raw, tx_nh_raw, tx_nav_raw;
  wire [10:0] tx_phase_raw;
  logic tx_bit_aligned, tx_nh_aligned, tx_nav_aligned;
  logic [10:0] tx_phase_aligned;
  wire capture, dump, wrong_capture, fixed_capture, zero_capture;
  wire [10:0] cap_phase, result_phase, candidate, local_index;
  wire [31:0] window_id;
  wire [13:0] in_window;
  wire local_bit;
  wire signed [23:0] ir,qr,ia,qa;
  wire signed [5:0] pi,pq;
  wire signed [3:0] cos_local,sin_local;
  wire [24:0] mag;
  wire [48:0] energy;
  always #1 clk=~clk; // compressed waveform time; 16368 accepted samples = nominal 1 ms.
  bdi_signal_source source (
    .clk_16m368(clk),.rst_n(rst_n),.enable(enable_source),.if_sample(if_sample),.if_valid(if_valid),
    .dbg_nav_bit(tx_nav_raw),.dbg_nh_bit(tx_nh_raw),.dbg_prn_bit(tx_bit_raw),
    .dbg_prn_phase(tx_phase_raw),.dbg_nh_idx(),.dbg_nav_idx());
  // Align the combinational source debug ports with its registered IF output.
  always @(posedge clk) begin
    tx_bit_aligned <= tx_bit_raw; tx_phase_aligned <= tx_phase_raw;
    tx_nh_aligned <= tx_nh_raw; tx_nav_aligned <= tx_nav_raw;
  end
  bdi_sliding_correlator dut (
    .clk(clk),.rst_n(rst_n),.start(start),.if_sample(if_sample),.if_valid(if_valid),
    .ready(ready),.bad_prn(),.capture(capture),.capture_phase(cap_phase),.dump(dump),
    .i_result(ir),.q_result(qr),.magnitude(mag),.energy(energy),.result_phase(result_phase),.candidate_phase(candidate),
    .result_window(window_id),.sample_in_window(in_window),.local_index(local_index),.local_prn_bit(local_bit),
    .local_cos(cos_local),.local_sin(sin_local),.product_i(pi),.product_q(pq),.i_acc(ia),.q_acc(qa));
  bdi_sliding_correlator #(.PRN(5)) wrong_code (
    .clk(clk),.rst_n(rst_n),.start(start),.if_sample(if_sample),.if_valid(if_valid),
    .ready(wrong_ready),.bad_prn(),.capture(wrong_capture));
  bdi_sliding_correlator #(.AUTO_STEP(1'b0)) wrong_phase (
    .clk(clk),.rst_n(rst_n),.start(start),.if_sample(if_sample),.if_valid(if_valid),
    .ready(fixed_ready),.bad_prn(),.capture(fixed_capture));
  bdi_sliding_correlator zero_input (
    .clk(clk),.rst_n(rst_n),.start(start),.if_sample(2'sd0),.if_valid(if_valid),
    .ready(zero_ready),.bad_prn(),.capture(zero_capture));

  integer fd, trace_fd, waves;
  string output_path, trace_path, wave_path;
  integer samples=0, windows=0, checked_code_samples=0, gap_cycles=0;
  integer exp_phase=0, ref_i=0, ref_q=0, local_chip, tx_chip;
  integer expected_sample, expected_i_product, expected_q_product;
  integer ref_mag, exp_cos, exp_sin, n, c;
  logic held_capture=0;
  logic trace_this;
  localparam logic [19:0] NH=20'b00000100110101001110;

  always @(negedge clk) if(rst_n && run_source) begin
    cycle_count=cycle_count+1;
    pause_source=(gap_period>0 && cycle_count%gap_period==0);
    if(pause_source) gap_cycles=gap_cycles+1;
  end

  always @(posedge clk) if(rst_n) begin
    if(if_valid && ready) begin
      n=samples%16368;
      // Independent chronological source reference, not a DUT phase/ROM read.
      tx_chip=meo6_code_bit(11'((10+n/8)%2046));
      local_chip=meo6_code_bit(11'((exp_phase+n/8)%2046));
      expected_sample=(samples%4==0) ? 1 : (samples%4==2 ? -1 : 0);
      if(1'b1 ^ NH[19-(samples/16368)%20] ^ tx_chip) expected_sample=-expected_sample;
      if($signed(if_sample)!==expected_sample || tx_bit_aligned!==1'(tx_chip))
        $fatal(1,"source/sign/debug alignment mismatch at sample %0d",samples);
      if(local_bit!==1'(local_chip) || local_index!=11'((exp_phase+n/8)%2046))
        $fatal(1,"independent local code mismatch at sample %0d",samples);
      if(exp_phase==10) begin
        if(local_bit!==tx_bit_aligned || local_index!=tx_phase_aligned)
          $fatal(1,"aligned TX/local code mismatch at sample %0d",samples);
        checked_code_samples=checked_code_samples+1;
      end
      case((samples+1)%4)
        0: begin exp_cos=7; exp_sin=0; end
        1: begin exp_cos=0; exp_sin=7; end
        2: begin exp_cos=-7; exp_sin=0; end
        3: begin exp_cos=0; exp_sin=-7; end
      endcase
      expected_i_product=expected_sample*exp_cos*(local_chip ? -1 : 1);
      expected_q_product=expected_sample*exp_sin*(local_chip ? -1 : 1);
      if($signed(pi)!==expected_i_product || $signed(pq)!==expected_q_product)
        $fatal(1,"mix/despread mismatch at sample %0d",samples);
      ref_i=ref_i+expected_i_product; ref_q=ref_q+expected_q_product;
      // Selected complete wrong/correct windows plus each dump neighborhood.
      trace_this=trace_fd && (windows==0 || windows==10 || n<3 || n>=16365);
      if(trace_this)
        $fwrite(trace_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,",cycle_count,samples,windows+1,n,exp_phase,$signed(if_sample),tx_bit_aligned,local_bit,$signed(pi),$signed(pq),$signed(ia),$signed(qa),$signed(ir),$signed(qr));
      samples=samples+1;
      #0.01;
      if(trace_this)
        $fdisplay(trace_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",dump,capture,candidate,$signed(ia),$signed(qa),$signed(ir),$signed(qr),mag);
      if(n==16367) begin
        windows=windows+1;
        ref_mag=(ref_i<0 ? -ref_i : ref_i)+(ref_q<0 ? -ref_q : ref_q);
        if(!dump || result_phase!=exp_phase || $signed(ir)!=ref_i || $signed(qr)!=ref_q || mag!=ref_mag || window_id!=windows)
          $fatal(1,"result/dump/phase mismatch at window %0d",windows);
        if(!held_capture && ref_mag>=8192) begin
          if(windows!=11 || exp_phase!=10) $fatal(1,"unexpected acquisition window/phase");
          held_capture=1;
        end
        if(capture!==held_capture || (capture && cap_phase!=10)) $fatal(1,"incorrect capture timing/phase");
        $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",windows,result_phase,$signed(ir),$signed(qr),mag,energy,capture,samples);
        $display("BDI window=%0d phase=%0d I=%0d Q=%0d M=%0d capture=%0d samples=%0d",windows,result_phase,$signed(ir),$signed(qr),mag,capture,samples);
        if(!held_capture) exp_phase=(exp_phase+1)%2046;
        ref_i=0; ref_q=0;
      end else if(dump) $fatal(1,"dump before 16368 accepted samples");
      if(wrong_capture || fixed_capture || zero_capture) $fatal(1,"negative control falsely acquired");
    end else begin
      #0.01;
      if(dump) $fatal(1,"dump exceeded one clock or invalid input advanced a window");
    end
  end
  initial begin
    if(!$value$plusargs("OUTPUT=%s",output_path)) output_path="reports/sim/bdi_capture.csv";
    if(!$value$plusargs("TRACE=%s",trace_path)) trace_path="reports/sim/bdi_trace.csv";
    if(!$value$plusargs("GAP_PERIOD=%d",gap_period)) gap_period=0;
    fd=$fopen(output_path,"w"); trace_fd=$fopen(trace_path,"w");
    if(!fd || !trace_fd) $fatal(1,"cannot open BDI evidence files");
    $fdisplay(fd,"window,phase,i,q,magnitude,energy,capture,accepted_samples");
    $fdisplay(trace_fd,"cycle,sample,window,offset,phase,if_sample,tx_prn,local_prn,product_i,product_q,acc_i_before,acc_q_before,result_i_before,result_q_before,dump_after,capture_after,candidate_after,acc_i_after,acc_q_after,result_i_after,result_q_after,magnitude_after");
    if($value$plusargs("WAVE=%s",wave_path)) begin
      $dumpfile(wave_path);
      $dumpvars(0,clk,rst_n,if_sample,if_valid,tx_bit_aligned,tx_bit_raw,tx_phase_aligned,
        local_bit,local_index,candidate,result_phase,cap_phase,dump,capture,ir,qr,mag,ia,qa,pi,pq,cos_local,sin_local,in_window);
    end
    repeat(5) @(negedge clk); rst_n=1;
    @(negedge clk); start=1;
    @(negedge clk); start=0;
    wait(ready && wrong_ready && fixed_ready && zero_ready);
    @(negedge clk); run_source=1;
    wait(windows==13);
    @(negedge clk); run_source=0;
    if(checked_code_samples!=3*16368 || samples!=13*16368 || !capture || (gap_period>0 && gap_cycles==0))
      $fatal(1,"missing full-code comparisons, confirmation windows or gap coverage");
    $fclose(fd); $fclose(trace_fd);
    // A second independent reset must not retain the historical capture latch.
    rst_n=0; #0.01;
    if(capture || dump || wrong_capture || fixed_capture || zero_capture) $fatal(1,"reset retained capture");
    $display("TEST PASSED: teacher source, 13 windows, 49104 aligned code samples, 3 negative controls, reset; gaps=%0d",gap_cycles);
    $finish;
  end
  initial begin #3000000; $fatal(1,"teacher BDI capture timeout"); end
endmodule
