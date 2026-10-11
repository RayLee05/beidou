module tb_teacher_stream_frontend;
  logic clk = 0, rst_n = 0, start = 0;
  always #5 clk = ~clk;
  logic [1:0] valid = 0, last = 0, ready, sv, sl, sr;
  logic [31:0] data[2];
  logic [63:0] tag[2], count[2], missing[2];
  logic signed [2:0] sample[2];
  logic [1:0] bad;
  integer seen[2] = '{0,0};
  integer final_seen[2] = '{0,0};
  integer errors = 0, cycles = 0;
  logic [31:0] words[3] = '{32'h1be4936c,32'h72d8914e,32'hc1b687e4};
  logic inject_gap = 0;
  generate for (genvar g=0; g<2; g++) begin : gen_fe
    teacher_stream_frontend #(.MODE(g)) dut (
      .clk(clk), .rst_n(rst_n), .start(start), .stream_data(data[g]),
      .stream_valid(valid[g]), .stream_last(last[g]), .transfer_index(tag[g]),
      .stream_ready(ready[g]), .sample(sample[g]), .sample_valid(sv[g]),
      .sample_last(sl[g]), .sample_ready(sr[g]), .sample_count(count[g]),
      .input_error(bad[g]), .missing_ticks(missing[g]));
    assign sr[g] = (cycles%7 != 2 && cycles%7 != 3);
    always @(posedge clk) if (rst_n && sv[g] && sr[g]) begin
      integer w, s, p, expected;
      w = seen[g]/(g==1 ? 16 : 4); s = seen[g]%(g==1 ? 16 : 4);
      p = g==1 ? (s/4)*8+6-2*(s%4) : 2*s;
      expected = 2*int'(words[w][p+:2])-3;
      if ($signed(sample[g]) !== expected || sl[g] !== (w==2 && s==(g==1 ? 15 : 3))) begin
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
      tag[m]=64'(w*4 + (inject_gap && w==2 ? 4 : 0));
      do @(posedge clk); while (!ready[m]);
      @(negedge clk); valid[m]=0;
    end
  endtask
  initial begin
    data[0]=0; data[1]=0; tag[0]=0; tag[1]=0;
    for (int run=0; run<2; run++) begin
      rst_n=0; start=0; inject_gap=(run==1);
      seen[0]=0; seen[1]=0; final_seen[0]=0; final_seen[1]=0;
      repeat(3) @(negedge clk); rst_n=1;
      if (ready !== 0) $fatal(1,"ready before start");
      start=1; @(negedge clk); start=0;
      fork feed(0); feed(1); join
      wait (count[0]==12 && count[1]==48);
      repeat(5) @(negedge clk);
      if (bad !== (inject_gap ? 2'b11 : 2'b00) || missing[0] !== (inject_gap ? 64'd4 : 64'd0)
          || missing[1] !== (inject_gap ? 64'd16 : 64'd0) || ready !== 0
          || final_seen[0]!=1 || final_seen[1]!=1) $fatal(1,"count/tag/last mismatch");
      start=1; repeat(3) @(negedge clk); start=0;
      if (ready !== 0 || count[0]!=12 || count[1]!=48) $fatal(1,"unexpected restart");
    end
    if (errors==0) $display("TEST PASSED"); else $display("TEST FAILED: %0d",errors);
    $finish;
  end
  initial begin #100000; $fatal(1,"timeout"); end
endmodule
