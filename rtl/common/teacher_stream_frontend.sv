// Current teacher player MODE=2: 16 samples, stream_data[1:0] earliest;
// sample_index advances by 16. The player already reverses file-byte pairs.
// Legacy teacher player MODE=1: four file bytes per transfer, 16 IF2 samples;
// byte 0 is stream_data[7:0], and its most significant pair comes first.
// Legacy contract MODE=0: four samples in stream_data[7:0], earliest at [1:0].
// Transfer tags are checked separately from the actual accepted sample count.
module teacher_stream_frontend #(
  parameter integer MODE = 2,
  parameter integer TAG_STRIDE = MODE == 2 ? 16 : 4
) (
  input logic clk, rst_n, start,
  input logic [31:0] stream_data,
  input logic stream_valid, stream_last,
  input logic [63:0] transfer_index,
  output logic stream_ready,
  output logic signed [2:0] sample,
  output logic sample_valid, sample_last,
  input logic sample_ready,
  output logic [63:0] sample_count,
  output logic input_error,
  output logic [63:0] missing_ticks
);
  localparam integer SAMPLES = MODE == 0 ? 4 : 16;
  logic [31:0] word_q;
  logic [4:0] index_q;
  logic full, last_q, active, started;
  logic [63:0] expected_tag;
  integer bitpos;
  wire take_sample = sample_valid && sample_ready;
  wire take_word = stream_valid && stream_ready;

  initial begin
    if (MODE != 0 && MODE != 1 && MODE != 2) $fatal(1, "Unsupported stream MODE");
    if (TAG_STRIDE < 1 || SAMPLES % TAG_STRIDE != 0)
      $fatal(1, "TAG_STRIDE must divide samples per transfer");
  end
  assign stream_ready = active && (!full ||
      (take_sample && index_q == SAMPLES-1 && !last_q));
  assign sample_valid = full;
  assign sample_last = full && last_q && index_q == SAMPLES-1;
  always_comb begin
    bitpos = MODE == 1 ? (int'(index_q) / 4) * 8 + 6 - 2 * (int'(index_q) % 4)
                       : 2 * int'(index_q);
    case (word_q[bitpos +: 2])
      2'b00: sample = -3'sd3;
      2'b01: sample = -3'sd1;
      2'b10: sample = 3'sd1;
      default: sample = 3'sd3;
    endcase
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      word_q <= '0; index_q <= '0; full <= 1'b0; last_q <= 1'b0;
      active <= 1'b0; started <= 1'b0; expected_tag <= '0;
      sample_count <= '0; input_error <= 1'b0; missing_ticks <= '0;
    end else begin
      if (start && !started) begin active <= 1'b1; started <= 1'b1; end
      if (take_sample) begin
        sample_count <= sample_count + 64'd1;
        if (index_q == SAMPLES-1) begin
          full <= 1'b0; index_q <= '0;
          if (last_q) active <= 1'b0;
        end else index_q <= index_q + 5'd1;
      end
      // Refill after draining the previous word, including the same cycle.
      if (take_word) begin
        word_q <= stream_data; last_q <= stream_last; full <= 1'b1; index_q <= '0;
        expected_tag <= transfer_index + 64'(TAG_STRIDE);
        if (transfer_index != expected_tag) begin
          input_error <= 1'b1;
          missing_ticks <= missing_ticks + (transfer_index > expected_tag
              ? (transfer_index - expected_tag) * 64'(SAMPLES / TAG_STRIDE) : 64'd1);
        end
      end
    end
  end
endmodule
