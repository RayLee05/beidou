`timescale 1ns/1ps
// Independent ordering check: compare every unpacked sample with chronological
// MSB-first file pairs, never with a reordered copy of stream_data.
module tb_teacher_player_order #(
  parameter integer STREAM_MODE = 2,
  parameter integer TAG_STRIDE = STREAM_MODE == 2 ? 16 : 4
);
  logic clk=0, reset_n=0, start=0;
  always #5 clk=~clk;
  logic [31:0] stream_data;
  logic stream_valid, stream_ready, stream_last, player_done, player_error;
  logic [63:0] sample_index, sample_count, missing_ticks;
  logic signed [2:0] sample;
  logic sample_valid, sample_ready, sample_last, input_error;
  longint seen=0, words=0, expected_samples=0, cycles=0;
  integer reference_fd, byte_value, last_count=0, expected;
  logic held=0;
  logic signed [2:0] held_sample;
  logic held_last;
  string input_path;

  if2_file_player player (
    .clk(clk), .reset_n(reset_n), .start(start), .stream_data(stream_data),
    .stream_valid(stream_valid), .stream_ready(stream_ready), .stream_last(stream_last),
    .sample_index(sample_index), .busy(), .done(player_done), .error(player_error));
  teacher_stream_frontend #(.MODE(STREAM_MODE), .TAG_STRIDE(TAG_STRIDE)) frontend (
    .clk(clk), .rst_n(reset_n), .start(start), .stream_data(stream_data),
    .stream_valid(stream_valid), .stream_last(stream_last), .transfer_index(sample_index),
    .stream_ready(stream_ready), .sample(sample), .sample_valid(sample_valid),
    .sample_last(sample_last), .sample_ready(sample_ready), .sample_count(sample_count),
    .input_error(input_error), .missing_ticks(missing_ticks));
  always @(negedge clk) if (reset_n) begin
    cycles++;
    sample_ready=(cycles%11!=2 && cycles%11!=3 && cycles%11!=4);
    if (cycles>expected_samples*3+1000) $fatal(1,"stream order timeout");
  end
  always @(posedge clk) if (reset_n) begin
    if (stream_valid && stream_ready) begin
      if (sample_index!==64'(words*TAG_STRIDE)) $fatal(1,"transfer tag/order mismatch");
      words++;
    end
    if (held && (!sample_valid || sample!==held_sample || sample_last!==held_last))
      $fatal(1,"sample changed under backpressure");
    held=sample_valid && !sample_ready;
    held_sample=sample; held_last=sample_last;
    if (sample_valid && sample_ready) begin
      if (seen>=expected_samples) $fatal(1,"extra unpacked sample");
      if (seen%4==0) begin
        byte_value=$fgetc(reference_fd);
        if (byte_value<0) $fatal(1,"reference input underrun");
      end
      expected=2*((byte_value>>(6-2*(seen%4))) & 3)-3;
      if ($signed(sample)!==expected)
        $fatal(1,"sample order mismatch at %0d: rtl=%0d file=%0d",seen,sample,expected);
      if (sample_last!==(seen==expected_samples-1)) $fatal(1,"incorrect final sample marker");
      if (sample_last) last_count++;
      seen++;
    end
  end
  initial begin
    sample_ready=0;
    if (!$value$plusargs("INPUT=%s",input_path) ||
        !$value$plusargs("EXPECTED_SAMPLES=%d",expected_samples) || expected_samples<=0)
      $fatal(1,"INPUT and EXPECTED_SAMPLES required");
    reference_fd=$fopen(input_path,"rb");
    if (reference_fd==0) $fatal(1,"reference file open failed");
    repeat(4) @(negedge clk); reset_n=1;
    @(negedge clk); start=1; @(negedge clk); start=0;
    wait(player_done && seen==expected_samples);
    repeat(5) @(negedge clk);
    if (player_error || input_error || missing_ticks!=0 || sample_count!=expected_samples
        || last_count!=1 || sample_valid || stream_ready)
      $fatal(1,"stream count/tag/last/error mismatch");
    $fclose(reference_fd);
    $display("TEST PASSED: compared %0d chronological samples, %0d transfers, mode=%0d stride=%0d",
             seen,words,STREAM_MODE,TAG_STRIDE);
    $finish;
  end
endmodule
