// Small hierarchical supply-import check; not part of the receiver file list.
module hier_power_probe(input wire clk, rst_n, data, output wire result0, result1);
  bds_pad_probe u0 (.clk(clk), .rst_n(rst_n), .data(data), .result(result0));
  bds_pad_probe u1 (.clk(clk), .rst_n(rst_n), .data(data), .result(result1));
endmodule
