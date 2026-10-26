// Exercise real input bits; no forced decoder state or internal BCH functions.
module tb_d1_robustness;
  logic clk=0,rst_n=0,clear=0,bit_valid=0,bit_val=0;
  always #5 clk=~clk;
  logic [31:0] bit_ms=0;
  logic [63:0] bit_end_sample=0;
  logic [47:0] bit_end_phase=0;
  logic sf_valid,sf_err,frame_synced,anchor_valid,week_valid,sf_inverted;
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
  logic [299:0] frames [0:15];
  logic [223:0] expected_info [0:15];
  integer expected_id [0:15], expected_sow [0:15];
  integer target=0,target_slot=0,target_flip=-1,target_inverted=0;
  integer got=0,rejected=0,bch_checks=0,metadata_checks=0;
  logic allow_output=1;
  logic [31:0] ms0=1003;
  function automatic logic [63:0] tag_sample(input integer idx);
    return 64'd100000+64'(idx)*64'd327360+64'(idx%7)*64'd10;
  endfunction
  function automatic logic [47:0] tag_phase(input integer idx);
    return {11'(idx%2046),37'(idx*134713)};
  endfunction
  d1_frame_sync #(.WITH_METADATA(1)) dut (.*);
  always @(negedge clk) if (rst_n && !clear) begin
    if (sf_err) rejected++;
    if (sf_valid) begin
      if (!allow_output) $fatal(1,"accepted an inconsistent or incomplete subframe");
      if (sf_info!==expected_info[target] || sf_id!=expected_id[target] ||
          sf_sow!=expected_sow[target] || sf_start_ms!==ms0+32'(20*target_slot) ||
          sf_inverted!=1'(target_inverted))
        $fatal(1,"D1 decoded data, polarity, or start time mismatch");
      if (sf_fixes!=((target_flip>=0)?1:0)) $fatal(1,"BCH correction count mismatch");
      if (anchor_ms!==sf_start_ms || anchor_sow!==sf_sow || !anchor_valid || !frame_synced)
        $fatal(1,"time anchor not committed with subframe");
      for (int w=0;w<10;w++) begin
        if (sf_word_samples[w]!==tag_sample(target_slot+29+30*w) ||
            sf_word_phases[w]!==tag_phase(target_slot+29+30*w) ||
            sf_word_ms[w]!==ms0+32'(20*(target_slot+30+30*w)))
          $fatal(1,"word-end metadata mismatch at word %0d",w);
        if (sf_word_fixes[w]!=((target_flip>=0 && target_flip/30==w)?1:0))
          $fatal(1,"per-word correction count mismatch");
        metadata_checks++;
      end
      for (int b=0;b<300;b++)
        if (sf_raw[299-b] !== (frames[target][299-b] ^ (b==target_flip)))
          $fatal(1,"raw input word incorrectly changed by BCH or polarity");
      got++;
    end
  end
  task automatic reset_search;
    clear=1; bit_valid=0;
    @(negedge clk); clear=0; got=0; rejected=0; allow_output=1;
  endtask
  task automatic feed(input bit value,input integer idx);
    bit_valid=1; bit_val=value; bit_ms=ms0+32'(20*idx);
    bit_end_sample=tag_sample(idx); bit_end_phase=tag_phase(idx);
    @(negedge clk); bit_valid=0;
    repeat(2) @(negedge clk);
  endtask
  task automatic candidate(input integer frame_idx,input integer slot,
                            input integer first=0,input integer flip=-1,
                            input integer inverted=0,input integer skip=-1);
    target=frame_idx; target_slot=slot; target_flip=flip; target_inverted=inverted;
    for (int b=first;b<300;b++)
      if (b!=skip) feed(frames[frame_idx][299-b] ^ (b==flip) ^ 1'(inverted),slot+b);
    for (int b=0;b<11;b++) feed(frames[0][299-b] ^ 1'(inverted),slot+300+b);
    repeat(30) @(negedge clk);
  endtask
  integer fd,rc;
  initial begin
    $readmemh("tb/vectors/sync_frames.hex",frames);
    fd=$fopen("tb/vectors/sync_frames_expected.txt","r");
    if (!fd) $fatal(1,"run scripts/gen_unit_vectors.py first");
    for (int i=0;i<16;i++) begin
      rc=$fscanf(fd,"%d %d %h\n",expected_id[i],expected_sow[i],expected_info[i]);
      if (rc!=3) $fatal(1,"missing expected frame");
    end
    $fclose(fd);
    repeat(3) @(negedge clk); rst_n=1;

    // Exact same two preambles can surround a hole in the input bit stream.
    reset_search(); allow_output=0; candidate(0,0,0,-1,0,60);
    if (got || anchor_valid || frame_synced) $fatal(1,"bridged a missing input bit");
    allow_output=1; candidate(1,300,11);
    if (got!=1) $fatal(1,"failed to recover after missing bit");
    feed(0,610); // duplicate of the last preamble bit's label
    if (anchor_valid || frame_synced || week_valid) $fatal(1,"duplicate bit retained stale time");

    // Week-boundary SOW rollover, FraID 5 -> 1, and 32-bit label rollover.
    reset_search(); ms0=32'hfffff800;
    candidate(0,0);
    for (int i=1;i<4;i++) candidate(i,300*i,11);
    if (got!=4 || !week_valid || week!=951) $fatal(1,"week/id/time rollover");
    ms0=1003;

    for (int bad=12;bad<16;bad++) begin
      reset_search(); candidate(0,0);
      allow_output=0; candidate(bad,300,11);
      if (got!=1 || rejected!=1 || anchor_sow!=604788) $fatal(1,"bad header modified time anchor");
      allow_output=1; candidate(2,600,11);
      if (got!=2 || !week_valid) $fatal(1,"rejected frame prevented coherent recovery");
    end
    // Two entire undecodable subframes may be skipped without a false anchor.
    reset_search(); candidate(0,0);
    allow_output=0;
    for (int i=311;i<900;i++) feed(0,i);
    allow_output=1; candidate(3,900);
    if (got!=2 || sf_sow!=6 || sf_id!=2) $fatal(1,"two-subframe gap recovery");

    // Age counts received bits rather than wall-clock idle cycles.
    reset_search(); candidate(2,0);
    repeat(1500) @(negedge clk);
    if (!anchor_valid || !week_valid) $fatal(1,"idle clocks expired a valid anchor");
    allow_output=0;
    for (int i=311;i<1510;i++) feed(0,i);
    if (!anchor_valid) $fatal(1,"time anchor expired before 1200 input bits");
    feed(0,1510);
    if (anchor_valid || frame_synced || week_valid) $fatal(1,"stale frame/time/week never expires");
    allow_output=1; candidate(4,1511);
    if (got!=2) $fatal(1,"cannot reacquire after expiry");

    // Exhaust every protected transmitted bit, alternating overall polarity.
    for (int error_bit=15;error_bit<300;error_bit++) begin
      reset_search(); candidate(0,0,0,error_bit,error_bit%2);
      if (got!=1) $fatal(1,"single BCH error not recovered at bit %0d",error_bit);
      bch_checks++;
    end
    $display("D1 gaps/duplicates, SOW/FraID continuity and rollover, timeout recovery: PASS");
    $display("%0d protected-bit errors corrected; %0d word-end metadata entries checked",bch_checks,metadata_checks);
    $display("TEST PASSED"); $finish;
  end
  initial begin #20000000; $fatal(1,"D1 robustness timeout"); end
endmodule
