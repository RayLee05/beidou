module tb_teacher_stream_frontend;
  logic clk = 0, rst_n = 0, start = 0;
  always #5 clk = ~clk;
  logic [2:0] valid = 0, last = 0, ready, sv, sl, sr;
  logic [31:0] data[3];
  logic [63:0] tag[3], count[3], missing[3];
  logic signed [2:0] sample[3];
  logic [2:0] bad;
  integer seen[3] = '{0,0,0};
  integer final_seen[3] = '{0,0,0};
  integer errors = 0, cycles = 0;
  logic [31:0] words[3] = '{32'h1be4936c,32'h72d8914e,32'hc1b687e4};
  integer tag_error = 0; // 0: continuous; 1: one missing transfer; 2: duplicate tag
  generate for (genvar g=0; g<3; g++) begin : gen_fe
    teacher_stream_frontend #(.MODE(g)) dut (
      .clk(clk), .rst_n(rst_n), .start(start), .stream_data(data[g]),
      .stream_valid(valid[g]), .stream_last(last[g]), .transfer_index(tag[g]),
      .stream_ready(ready[g]), .sample(sample[g]), .sample_valid(sv[g]),
      .sample_last(sl[g]), .sample_ready(sr[g]), .sample_count(count[g]),
      .input_error(bad[g]), .missing_ticks(missing[g]));
    assign sr[g] = (cycles%7 != 2 && cycles%7 != 3);
    always @(posedge clk) if (rst_n && sv[g] && sr[g]) begin
      integer w, s, p, expected;
      if (seen[g]>=3*(g==0 ? 4 : 16)) $fatal(1,"unexpected extra sample");
      w = seen[g]/(g==0 ? 4 : 16); s = seen[g]%(g==0 ? 4 : 16);
      p = g==1 ? (s/4)*8+6-2*(s%4) : 2*s;
      expected = 2*int'(words[w][p+:2])-3;
      if ($signed(sample[g]) !== expected || sl[g] !== (w==2 && s==(g==0 ? 3 : 15))) begin
        $display("ERROR: MODE=%0d sample=%0d got=%0d expected=%0d last=%0d",g,seen[g],sample[g],expected,sl[g]);
        errors++;
      end
      if (sl[g]) final_seen[g]++;
      seen[g]++;
    end
  end endgenerate
  always @(negedge clk) cycles++;
  task automatic feed(input integer m);
    for (int w=0; w<3; w++) begin
      @(negedge clk); valid[m]=1; data[m]=words[w]; last[m]=(w==2);
      tag[m]=64'((m==2 ? 16 : 4)*(w + (w==2 ? (tag_error==1 ? 1 : tag_error==2 ? -1 : 0) : 0)));
      do @(posedge clk); while (!ready[m]);
      @(negedge clk); valid[m]=0;
    end
  endtask
  initial begin
    for (int m=0; m<3; m++) begin data[m]=0; tag[m]=0; end
    for (int run=0; run<3; run++) begin
      rst_n=0; start=0; tag_error=run;
      for (int m=0; m<3; m++) begin seen[m]=0; final_seen[m]=0; end
      repeat(3) @(negedge clk); rst_n=1;
      if (ready !== 0) $fatal(1,"ready before start");
      start=1; @(negedge clk); start=0;
      fork feed(0); feed(1); feed(2); join
      wait (count[0]==12 && count[1]==48 && count[2]==48);
      repeat(5) @(negedge clk);
      if (bad !== (run!=0 ? 3'b111 : 3'b000) || missing[0] !== (run==1 ? 64'd4 : run==2 ? 64'd1 : 64'd0)
          || missing[1] !== (run==1 ? 64'd16 : run==2 ? 64'd1 : 64'd0)
          || missing[2] !== (run==1 ? 64'd16 : run==2 ? 64'd1 : 64'd0) || ready !== 0
          || final_seen[0]!=1 || final_seen[1]!=1 || final_seen[2]!=1) $fatal(1,"count/tag/last mismatch");
      start=1; repeat(3) @(negedge clk); start=0;
      if (ready !== 0 || count[0]!=12 || count[1]!=48 || count[2]!=48) $fatal(1,"unexpected restart");
    end
    if (errors==0) $display("TEST PASSED"); else $display("TEST FAILED: %0d",errors);
    $finish;
  end
  initial begin #100000; $fatal(1,"timeout"); end
endmodule
