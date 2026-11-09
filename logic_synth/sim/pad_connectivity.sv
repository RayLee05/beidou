`timescale 1ns/1ps
// Uses the real vendor PAD model. Core boundary forcing isolates pin order and
// driver direction; receiver algorithms are covered separately by tb_six_signal.
module tb_pad_connectivity;
  reg [86:0] pins=0;
  wire [23:0] outputs;
  reg [23:0] expected=0;
  supply1 power_hi;
  supply0 ground_lo;
  bds_bb_6ch_pad_top dut (
    .POC(power_hi),.VDD(power_hi),.VDDPST(power_hi),.VSS(ground_lo),.VSSPST(ground_lo),
    .clk(pins[86]),.rst_n(pins[85]),.IF(pins[84:83]),.cfg_valid(pins[82]),
    .cfg_channel(pins[81:79]),.cfg_enable(pins[78]),.cfg_prn(pins[77:72]),
    .cfg_dop_min(pins[71:40]),.cfg_dop_step(pins[39:8]),.cfg_bins(pins[7:0]),
    .capture_ok(outputs[23:18]),.bit_sync_ok(outputs[17:12]),
    .nav_data(outputs[11:6]),.nav_valid(outputs[5:0]));
  initial begin
    force dut.core_out=expected;
    for(int i=0;i<87;i++) begin
      pins=87'd1<<i; #2;
      if(dut.core_in!==pins) $fatal(1,"input PAD bit order/receiver mismatch %0d",i);
    end
    pins='1;#2;if(dut.core_in!==pins) $fatal(1,"input pad all ones");
    pins='0;#2;if(dut.core_in!==pins) $fatal(1,"input pad all zero");
    for(int i=0;i<24;i++) begin
      expected=24'd1<<i;#2;
      if(outputs!==expected) $fatal(1,"output PAD bit order/enable mismatch %0d",i);
    end
    expected='1;#2;if(outputs!==expected) $fatal(1,"output pad all ones");
    expected='0;#2;if(outputs!==expected) $fatal(1,"output pad all zero");
    $display("TEST PASSED: 87 input and 24 output real PAD connections");$finish;
  end
endmodule
