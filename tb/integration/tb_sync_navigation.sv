// Prompt-to-D1 integration: no pre-decided bits are passed to the receiver.
// Time is compressed: 61 clocks per nominal 1 ms Prompt; labels keep code time.
`include "b1i_params.svh"
module tb_sync_navigation;
  logic clk=0,rst_n=0,clear=0,dump_valid=0,dump_partial=0;
  always #5 clk=~clk;
  localparam integer FIRST_BIT_MS=1013;
  localparam logic [19:0] NH=20'b00000100110101001110;
  logic [0:0] bits [0:4095];
  integer n_bits,n_sf,flip_at,exp_start[0:7],exp_id[0:7],exp_sow[0:7];
  logic [223:0] exp_info[0:7];
  integer want[0:4]='{0,1,2,4,5};
  logic [31:0] dump_ms=0,bit_ms,bit_mag;
  logic [63:0] dump_sample_count=0,bit_end_sample;
  logic [47:0] dump_code_phase=0,bit_end_phase;
  logic signed [CORR_ACC_W-1:0] i_p=0;
  logic synced,bit_valid,bit_val;
  logic [4:0] bit_phase;
  logic sf_valid,sf_inverted,frame_synced,anchor_valid,week_valid,sf_err;
  logic [2:0] sf_id;
  logic [19:0] sf_sow,anchor_sow;
  logic [31:0] sf_start_ms,anchor_ms;
  logic [223:0] sf_info;
  logic [4:0] sf_fixes;
  logic [12:0] week;
  logic [299:0] sf_raw;
  logic [9:0][1:0] sf_word_fixes;
  logic [9:0][63:0] sf_word_samples;
  logic [9:0][47:0] sf_word_phases;
  logic [9:0][31:0] sf_word_ms;
  integer got=0,word_checks=0,decoded_bits=0,total_fixes=0,result_fd;
  function automatic logic [63:0] sample_tag(input integer m);
    return 64'(m+1)*64'd16368+64'(m%7);
  endfunction
  function automatic logic [47:0] phase_tag(input integer m);
    return 48'(m)*48'd17897+48'd17;
  endfunction
  nh_bit_sync u_nh (.clk(clk),.rst_n(rst_n),.clear(clear),
    .dump_valid(dump_valid),.dump_partial(dump_partial),.dump_ms(dump_ms),
    .dump_sample_count(dump_sample_count),.dump_code_phase(dump_code_phase),.i_p(i_p),
    .synced(synced),.bit_phase(bit_phase),.bit_valid(bit_valid),.bit_val(bit_val),
    .bit_ms(bit_ms),.bit_mag(bit_mag),.bit_end_sample(bit_end_sample),.bit_end_phase(bit_end_phase));
  // Same invalidation rule as channel_slice: an NH loss invalidates D1 time.
  d1_frame_sync #(.WITH_METADATA(1)) u_d1 (.clk(clk),.rst_n(rst_n),
    .clear(clear | !synced),.bit_valid(bit_valid),.bit_val(bit_val),.bit_ms(bit_ms),
    .bit_end_sample(bit_end_sample),.bit_end_phase(bit_end_phase),
    .sf_valid(sf_valid),.sf_id(sf_id),.sf_sow(sf_sow),.sf_start_ms(sf_start_ms),.sf_info(sf_info),
    .sf_fixes(sf_fixes),.sf_raw(sf_raw),.sf_word_fixes(sf_word_fixes),
    .sf_word_samples(sf_word_samples),.sf_word_phases(sf_word_phases),.sf_word_ms(sf_word_ms),
    .sf_inverted(sf_inverted),.frame_synced(frame_synced),.anchor_valid(anchor_valid),
    .anchor_ms(anchor_ms),.anchor_sow(anchor_sow),.week(week),.week_valid(week_valid),.sf_err(sf_err));
  always @(negedge clk) if (rst_n && !clear) begin
    if (bit_valid) begin
      if (bit_ms<FIRST_BIT_MS || (bit_ms-FIRST_BIT_MS)%20!=0 ||
          bit_val!==bits[(bit_ms-FIRST_BIT_MS)/20][0])
        $fatal(1,"Prompt-to-bit decision or timestamp mismatch");
      decoded_bits++;
    end
    if (sf_err) $fatal(1,"unexpected frame rejection in coherent integration stream");
    if (sf_valid) begin
      if (got>=5) $fatal(1,"unexpected additional subframe");
      if (sf_id!=exp_id[want[got]] || sf_sow!=exp_sow[want[got]] ||
          sf_info!==exp_info[want[got]] || sf_start_ms!=FIRST_BIT_MS+20*exp_start[want[got]] ||
          sf_inverted!=(exp_start[want[got]]>=flip_at))
        $fatal(1,"Prompt-to-D1 information, time, or polarity mismatch");
      for (int w=0;w<10;w++) begin
        if (sf_word_samples[w]!==sample_tag(FIRST_BIT_MS+20*(exp_start[want[got]]+30*w+30)-1) ||
            sf_word_phases[w]!==phase_tag(FIRST_BIT_MS+20*(exp_start[want[got]]+30*w+30)-1) ||
            sf_word_ms[w]!==32'(FIRST_BIT_MS+20*(exp_start[want[got]]+30*w+30)))
          $fatal(1,"word-end time lost in NH-to-D1 integration");
        word_checks++;
      end
      $fwrite(result_fd,"%0d,%0d,%0d,%0d,%0d,%056h,%075h\n",
        sf_id,sf_sow,sf_start_ms,sf_fixes,sf_inverted,sf_info,sf_raw);
      $display("NH->D1: id=%0d sow=%0d start_ms=%0d fixes=%0d inverted=%0d",
        sf_id,sf_sow,sf_start_ms,sf_fixes,sf_inverted);
      total_fixes+=sf_fixes; got++;
    end
  end
  integer fd,rc,idx,k,m,noise;
  logic chip;
  initial begin
    $readmemh("tb/vectors/nav_bits.hex",bits);
    fd=$fopen("tb/vectors/nav_expected.txt","r");
    rc=$fscanf(fd,"%d %d %d\n",n_bits,n_sf,flip_at);
    if (rc!=3) $fatal(1,"missing navigation vectors");
    for (int i=0;i<n_sf;i++) begin
      rc=$fscanf(fd,"%d %d %d %h\n",exp_start[i],exp_id[i],exp_sow[i],exp_info[i]);
      if (rc!=4) $fatal(1,"missing expected subframe");
    end
    $fclose(fd);
    result_fd=$fopen("reports/sim/navigation_chain.csv","w");
    if (!result_fd) $fatal(1,"cannot create integration CSV");
    $fwrite(result_fd,"id,sow,start_ms,fixes,inverted,information,raw\n");
    repeat(3) @(negedge clk); rst_n=1;
    for (m=1003;m<FIRST_BIT_MS+20*n_bits;m++) begin
      idx=(m-FIRST_BIT_MS)/20;
      k=(m-FIRST_BIT_MS)%20;
      if (m<FIRST_BIT_MS) begin idx=-1; k=k+20; end
      chip=((idx<0)?1'b0:bits[idx][0]) ^ NH[19-k];
      noise=(m*7919)%100001-50000;
      i_p=(chip?-200000:200000)+26'(noise);
      dump_ms=32'(m); dump_partial=(m==1003); dump_valid=1;
      dump_sample_count=sample_tag(m); dump_code_phase=phase_tag(m);
      @(negedge clk); dump_valid=0; dump_partial=0;
      repeat(60) @(negedge clk);
    end
    repeat(100) @(negedge clk);
    if (got!=5 || word_checks!=50 || total_fixes!=1 ||
        !synced || bit_phase!=13 || !week_valid || week!=950)
      $fatal(1,"incomplete Prompt-to-D1 result: frames=%0d words=%0d bits=%0d",got,word_checks,decoded_bits);
    $fclose(result_fd);
    $display("%0d Prompt windows, %0d recovered bits, %0d subframes, %0d measured word ends, %0d BCH correction",
      m-1003,decoded_bits,got,word_checks,total_fixes);
    // Emulate an incomplete dump after successful navigation reception.
    dump_valid=1; dump_partial=1; dump_ms=32'(m);
    @(negedge clk); dump_valid=0; dump_partial=0;
    repeat(3) @(negedge clk);
    if (synced || frame_synced || anchor_valid || week_valid)
      $fatal(1,"NH loss did not invalidate downstream frame/time/week");
    $display("NH loss invalidates downstream navigation time: PASS");
    $display("TEST PASSED"); $finish;
  end
  initial begin #40000000; $fatal(1,"sync-navigation integration timeout"); end
endmodule
