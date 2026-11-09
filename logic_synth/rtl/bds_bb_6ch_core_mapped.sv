// Fixed default interface for bottom-up mapped-channel integration.
module bds_bb_6ch_core_mapped (
  input logic clk, rst_n,
  input logic [1:0] IF,
  input logic cfg_valid,
  input logic [2:0] cfg_channel,
  input logic cfg_enable,
  input logic [5:0] cfg_prn,
  input logic signed [31:0] cfg_dop_min, cfg_dop_step,
  input logic [7:0] cfg_bins,
  output logic [5:0] capture_ok, bit_sync_ok, nav_data, nav_valid
);
  logic signed [2:0] sample;
  always_comb begin
    case (IF)
      2'b00: sample = -3'sd3;
      2'b01: sample = -3'sd1;
      2'b10: sample =  3'sd1;
      2'b11: sample =  3'sd3;
    endcase
  end
  for (genvar i=0; i<6; i++) begin : g_ch
    bds_channel u_channel (
      .clk(clk), .rst_n(rst_n), .sample(sample),
      .cfg_write(cfg_valid && cfg_channel == 3'(i)), .cfg_enable(cfg_enable), .cfg_prn(cfg_prn),
      .cfg_dop_min(cfg_dop_min), .cfg_dop_step(cfg_dop_step), .cfg_bins(cfg_bins),
      .capture_ok(capture_ok[i]), .bit_sync_ok(bit_sync_ok[i]),
      .nav_data(nav_data[i]), .nav_valid(nav_valid[i]));
  end
endmodule
