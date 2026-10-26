// Behavioral checks: all NH phases, arbitrary first label, gaps and partials.
`include "b1i_params.svh"
module tb_nh_continuity;
  logic clk=0, rst_n=0, clear=0, dump_valid=0, dump_partial=0;
  always #5 clk=~clk;
  logic [31:0] dump_ms=0, bit_ms, bit_mag;
  logic signed [CORR_ACC_W-1:0] i_p=0;
  logic synced, bit_valid, bit_val;
  logic [4:0] bit_phase;
  logic [63:0] bit_end_sample;
  logic [47:0] bit_end_phase;
  localparam logic [19:0] NH=20'b00000100110101001110;
  integer phase=0, polarity=0, checked=0, checks_this_run=0;
  logic check_bits=0;
  nh_bit_sync #(.BS_BITS(4)) dut (
    .clk(clk),.rst_n(rst_n),.clear(clear),.dump_valid(dump_valid),
    .dump_partial(dump_partial),.dump_ms(dump_ms),.i_p(i_p),
    .dump_sample_count(64'(dump_ms+1)*64'd16368),
    .dump_code_phase(48'(dump_ms)*48'd17897+48'd17),
    .synced(synced),.bit_phase(bit_phase),.bit_valid(bit_valid),
    .bit_val(bit_val),.bit_ms(bit_ms),.bit_mag(bit_mag),
    .bit_end_sample(bit_end_sample),.bit_end_phase(bit_end_phase));

  function automatic logic data_bit(input integer m);
    integer b;
    b=(m-phase)/20;
    return ((b*17 + (b/3)*5 + (b/7))%11)<5;
  endfunction
  always @(negedge clk) if (rst_n && !clear && bit_valid && check_bits) begin
    if (bit_ms%20!=phase || (bit_val ^ 1'(polarity))!=data_bit(int'(bit_ms)))
      $fatal(1,"NH bit mismatch: phase=%0d got phase=%0d bit_ms=%0d bit=%0d",phase,bit_phase,bit_ms,bit_val);
    if (bit_end_sample!==64'(bit_ms+20)*64'd16368 ||
        bit_end_phase!==48'(bit_ms+19)*48'd17897+48'd17)
      $fatal(1,"NH bit-end metadata crossed a window boundary");
    if (bit_mag==0) $fatal(1,"zero-quality bit on nonzero aligned input");
    checked++; checks_this_run++;
  end
  task automatic reset_search;
    check_bits=0; clear=1;
    @(negedge clk); clear=0;
    checks_this_run=0;
  endtask
  task automatic feed(input integer m, input bit partial=0, input bit zero_input=0);
    integer k, noise, amp;
    k=(m-phase)%20;
    if (k<0) k=k+20;
    noise=(m*97)%10001-5000;
    // Alternate polarity, noise and the most-negative legal Prompt value.
    amp=(phase==19)?33554431:200000;
    i_p=(data_bit(m)^NH[19-k]^1'(polarity)) ? -amp : amp;
    if (phase==19 && i_p<0) i_p=-26'sd33554431-26'sd1;
    else if (phase!=19) i_p=i_p+26'(noise);
    if (zero_input) i_p=0;
    dump_ms=32'(m); dump_partial=partial; dump_valid=1;
    @(negedge clk); dump_valid=0; dump_partial=0;
    repeat(60) @(negedge clk);
  endtask
  initial begin
    repeat(3) @(negedge clk); rst_n=1;
    for (phase=0;phase<20;phase++) begin
      reset_search(); polarity=phase%2; check_bits=1;
      // Label 1003 is intentionally nonzero and is not a multiple of 20.
      for (int m=1003;m<1403;m++) feed(m);
      if (!synced || bit_phase!=phase || checks_this_run<10)
        $fatal(1,"phase search failed at %0d: got=%0d bits=%0d",phase,bit_phase,checks_this_run);
    end
    phase=13; polarity=0;
    reset_search(); check_bits=1;
    for (int m=1003;m<1403;m++) feed(m);
    // A missing complete window must invalidate the old lock immediately.
    check_bits=0; feed(1404);
    if (synced || bit_valid) $fatal(1,"NH retained lock across a missing dump");
    check_bits=1;
    for (int m=1405;m<1805;m++) feed(m);
    if (!synced || bit_phase!=phase) $fatal(1,"NH failed to reacquire after gap");
    check_bits=0; feed(1805,1);
    if (synced || bit_valid) $fatal(1,"NH retained lock across a partial window");
    check_bits=1;
    for (int m=1806;m<2206;m++) feed(m);
    if (!synced || bit_phase!=phase) $fatal(1,"NH failed to reacquire after partial");
    check_bits=0; feed(2205);
    if (synced || bit_valid) $fatal(1,"NH retained lock across a duplicate label");
    reset_search();
    for (int m=501;m<901;m++) feed(m,0,1);
    if (synced || bit_valid) $fatal(1,"NH synchronized to zero input");
    $display("20 NH phases, inverted polarity, noise, full-scale input, gap/partial/duplicate recovery: %0d bits checked",checked);
    $display("TEST PASSED"); $finish;
  end
  initial begin #20000000; $fatal(1,"NH continuity timeout"); end
endmodule
