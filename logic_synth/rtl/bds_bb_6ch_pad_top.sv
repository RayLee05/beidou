// tphn28hpcpgv18 with explicit PG ports; use the vendor *_pwr.v PAD model.
// POC/VDDPST use the IO rail, VDD the core rail, and VSS/VSSPST ground.
// TPBN28V CUP bond pads belong to the physical flow and have no DC timing db.
module bds_bb_6ch_pad_top (
  inout wire POC,VDD,VSS,VDDPST,VSSPST,
  input wire clk, rst_n,
  input wire [1:0] IF,
  input wire cfg_valid,
  input wire [2:0] cfg_channel,
  input wire cfg_enable,
  input wire [5:0] cfg_prn,
  input wire signed [31:0] cfg_dop_min, cfg_dop_step,
  input wire [7:0] cfg_bins,
  output wire [5:0] capture_ok, bit_sync_ok, nav_data, nav_valid
);
  // 87 input signal pads; bit positions are explicit and checked by the TB.
  wire [86:0] external_in = {clk,rst_n,IF,cfg_valid,cfg_channel,cfg_enable,
                            cfg_prn,cfg_dop_min,cfg_dop_step,cfg_bins};
  wire [86:0] core_in;
  wire [23:0] core_out;
  wire [23:0] external_out;
  wire core_clk, core_rst_n, core_cfg_valid, core_cfg_enable;
  wire [1:0] core_if;
  wire [2:0] core_cfg_channel;
  wire [5:0] core_cfg_prn;
  wire [31:0] core_cfg_dop_min,core_cfg_dop_step;
  wire [7:0] core_cfg_bins;
  assign {core_clk,core_rst_n,core_if,core_cfg_valid,core_cfg_channel,core_cfg_enable,
          core_cfg_prn,core_cfg_dop_min,core_cfg_dop_step,core_cfg_bins}=core_in;
  for(genvar i=0;i<87;i++) begin:g_input_pad
    // OEN=1 disables the tri-state driver; REN=1 disables the weak pulldown.
    PDDW04SDGZ_H_G u_pad (.I(1'b0),.OEN(1'b1),.REN(1'b1),.PAD(external_in[i]),.C(core_in[i])
`ifndef SYNTH_PG_BIND
      ,.POC(POC),.VDD(VDD),.VSS(VSS),.VDDPST(VDDPST),.VSSPST(VSSPST)
`endif
    );
  end
  for(genvar i=0;i<24;i++) begin:g_output_pad
    PDDW04SDGZ_H_G u_pad (.I(core_out[i]),.OEN(1'b0),.REN(1'b1),.PAD(external_out[i]),.C()
`ifndef SYNTH_PG_BIND
      ,.POC(POC),.VDD(VDD),.VSS(VSS),.VDDPST(VDDPST),.VSSPST(VSSPST)
`endif
    );
  end
  assign {capture_ok,bit_sync_ok,nav_data,nav_valid}=external_out;
`ifdef MAPPED_CHANNEL_CORE
  bds_bb_6ch_core_mapped u_core (
`else
  bds_bb_6ch_core u_core (
`endif
    .clk(core_clk),.rst_n(core_rst_n),.IF(core_if),
    .cfg_valid(core_cfg_valid),.cfg_channel(core_cfg_channel),.cfg_enable(core_cfg_enable),
    .cfg_prn(core_cfg_prn),.cfg_dop_min(core_cfg_dop_min),.cfg_dop_step(core_cfg_dop_step),
    .cfg_bins(core_cfg_bins),.capture_ok(core_out[23:18]),.bit_sync_ok(core_out[17:12]),
    .nav_data(core_out[11:6]),.nav_valid(core_out[5:0]));
endmodule
