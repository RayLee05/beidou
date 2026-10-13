`timescale 1ns/1ps
// Uses the original teacher file player. Unlike its template, this bench waits
// for the accepted END record after the final word has actually been consumed.
module tb_teacher_receiver #(
  parameter integer STREAM_MODE = 2,
  parameter integer TAG_STRIDE = STREAM_MODE == 2 ? 16 : 4
);
  logic clk=0, reset_n=0, start=0;
  always #5 clk=~clk;
  logic [31:0] stream_data;
  logic stream_valid, stream_ready, stream_last, player_done, player_error;
  logic [63:0] sample_index;
  logic [255:0] record_data;
  logic record_valid, record_ready=1, end_seen=0;
  integer fd, records=0, stall_period=0, drain=0;
  longint cycles=0, cycle_limit=0, expected_samples=0;
  string output_path;
  if2_file_player u_player (
    .clk(clk), .reset_n(reset_n), .start(start), .stream_data(stream_data),
    .stream_valid(stream_valid), .stream_ready(stream_ready), .stream_last(stream_last),
    .sample_index(sample_index), .busy(), .done(player_done), .error(player_error));
  student_receiver_core #(.STREAM_MODE(STREAM_MODE), .TAG_STRIDE(TAG_STRIDE)) dut (.*);
  always @(negedge clk) if (reset_n) begin
    cycles++;
    record_ready=(stall_period<2 || cycles%stall_period!=0);
    if (cycles>cycle_limit) $fatal(1,"receiver exceeded cycle limit");
  end
  always @(posedge clk) if (reset_n && record_valid && record_ready) begin
    if (end_seen) $fatal(1,"record after END");
    for (int i=0; i<32; i++) $fwrite(fd,"%c",record_data[8*i+:8]);
    records++;
    if (record_data[7:0]==6) begin
      if (record_data[95:32]!=64'(expected_samples) || record_data[19:18]!=0)
        $fatal(1,"END sample count or input/output error");
      end_seen=1;
    end
  end
  initial begin
    output_path="reports/sim/teacher_records.bin";
    void'($value$plusargs("OUTPUT=%s",output_path));
    if (!$value$plusargs("EXPECTED_SAMPLES=%d",expected_samples) || expected_samples<=0)
      $fatal(1,"EXPECTED_SAMPLES must be positive");
    void'($value$plusargs("STALL_PERIOD=%d",stall_period));
    cycle_limit=expected_samples*4+1000000;
    fd=$fopen(output_path,"wb"); if (fd==0) $fatal(1,"output file");
    repeat(8) @(negedge clk); reset_n=1;
    @(negedge clk); start=1; @(negedge clk); start=0;
    wait(player_done);
    while (!end_seen && drain<100000) begin @(negedge clk); drain++; end
    if (player_error || !end_seen) $fatal(1,"player error or missing END");
    repeat(5) @(negedge clk); $fclose(fd);
    $display("TEST PASSED: samples=%0d records=%0d cycles=%0d",expected_samples,records,cycles);
    $finish;
  end
endmodule
