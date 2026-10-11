// Drop-in implementation of the teacher's student_receiver_core interface.
// MODE=1 matches the supplied file player's actual byte mapping and tag stride.
// Use MODE=0 for a producer implementing the documented four-sample contract.
module student_receiver_core #(
  parameter integer STREAM_MODE = 1,
  parameter integer TAG_STRIDE = 4,
  parameter integer N_LANES = 64,
  parameter integer BUF_DEPTH = 33024
) (
  input logic clk, reset_n, start,
  input logic [31:0] stream_data,
  input logic stream_valid,
  output logic stream_ready,
  input logic stream_last,
  input logic [63:0] sample_index,
  output logic [255:0] record_data,
  output logic record_valid,
  input logic record_ready
);
  logic signed [2:0] sample;
  logic sample_valid, sample_ready, sample_last, input_error;
  logic [63:0] accepted_samples, missing_ticks;
  logic started, cfg_valid;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin started <= 1'b0; cfg_valid <= 1'b0; end
    else begin
      cfg_valid <= start && !started;
      if (start) started <= 1'b1;
    end
  end
  teacher_stream_frontend #(.MODE(STREAM_MODE), .TAG_STRIDE(TAG_STRIDE)) u_input (
    .clk(clk), .rst_n(reset_n), .start(start), .stream_data(stream_data),
    .stream_valid(stream_valid), .stream_last(stream_last), .transfer_index(sample_index),
    .stream_ready(stream_ready), .sample(sample), .sample_valid(sample_valid),
    .sample_last(sample_last), .sample_ready(sample_ready), .sample_count(accepted_samples),
    .input_error(input_error), .missing_ticks(missing_ticks));
  b1i_rx_top #(.N_LANES(N_LANES), .BUF_DEPTH(BUF_DEPTH),
              .DIRECT_SAMPLES(1'b1), .PUBLIC_RECORDS(1'b1), .AUTO_SCAN(1'b1)) u_rx (
    .clk(clk), .rst_n(reset_n), .byte_valid(1'b0), .data_byte(8'd0), .byte_ready(),
    .direct_valid(sample_valid), .direct_sample(sample), .direct_last(sample_last),
    .direct_input_error(input_error), .direct_missing_ticks(missing_ticks), .direct_ready(sample_ready),
    .sram_run(1'b0), .sram_pace_en(1'b0), .sram_pace_inc(32'd0), .sram_sample_total(32'd0),
    .sram_rd(), .sram_addr(), .sram_rdata(8'd0), .sram_rvalid(1'b0), .sram_done(),
    .cfg_valid(cfg_valid), .cfg_addr(8'h00), .cfg_wdata(32'd1), .cfg_ready(), .cfg_rdata(),
    .rec_valid(record_valid), .rec_ready(record_ready), .rec_data(record_data), .rec_last(),
    .ch_locked(), .ch_bit_valid(), .ch_nav_valid(), .error_valid(), .error_code());
endmodule
