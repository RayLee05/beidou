// Clear during final BCH/field validation must cancel the old channel's subframe.
module tb_d1_clear;
  logic clk = 0, rst_n = 0, clear = 0, bit_valid = 0, bit_val = 0;
  always #5 clk = ~clk;
  logic [31:0] bit_ms = 0;
  wire sf_valid, frame_synced, anchor_valid, week_valid;
  wire [223:0] sf_info;
  reg [0:0] vector_bits [0:2236];
  integer errors = 0, got = 0, i;
  d1_frame_sync dut (
    .clk(clk), .rst_n(rst_n), .clear(clear), .bit_valid(bit_valid), .bit_val(bit_val),
    .bit_ms(bit_ms), .sf_valid(sf_valid), .sf_id(), .sf_sow(), .sf_start_ms(),
    .sf_info(sf_info), .sf_fixes(), .sf_inverted(), .frame_synced(frame_synced),
    .anchor_valid(anchor_valid), .anchor_ms(), .anchor_sow(), .week(),
    .week_valid(week_valid), .sf_err());
  always @(posedge clk) if (sf_valid) got++;
  task automatic feed(input integer index);
    bit_valid = 1; bit_val = vector_bits[index][0]; bit_ms = 1000 + 20 * index;
    @(negedge clk);
    bit_valid = 0;
    @(negedge clk);
  endtask
  initial begin
    $readmemh("tb/vectors/nav_bits.hex", vector_bits);
    repeat (3) @(negedge clk); rst_n = 1;
    for (i = 0; i < 137 + 311; i++) feed(i);
    while (dut.cw != 19) @(negedge clk);
    clear = 1;
    @(negedge clk); clear = 0;
    repeat (30) @(negedge clk);
    if (got != 0 || sf_valid || frame_synced || anchor_valid || week_valid || sf_info !== 0) begin
      $display("FAIL: stale subframe committed after clear"); errors++;
    end
    // After cancellation a fresh pair of preambles must still decode normally.
    for (i = 137; i < 137 + 311; i++) feed(i);
    repeat (30) @(negedge clk);
    if (got != 1 || !frame_synced || !anchor_valid) begin
      $display("FAIL: cannot decode after clear, got=%0d", got); errors++;
    end
    if (errors == 0) $display("TEST PASSED");
    else $display("TEST FAILED: %0d", errors);
    $finish;
  end
  initial begin #100000; $display("TEST FAILED: timeout"); $finish; end
endmodule
