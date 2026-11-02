`timescale 1ns/1ps
// Layered control/NH integration test. Search results and 1-ms Prompt inputs
// are injected; PRN writes, channel FSMs and all six NH decoders are real RTL.
module tb_six_channel_control;
  logic clk=0,rst_n=0,cfg_valid=0,cfg_enable=0;
  always #5 clk=~clk;
  logic [2:0] cfg_channel=0;
  logic [5:0] cfg_prn=0;
  logic [5:0] capture_ok,bit_sync_ok,nav_data,nav_valid;
  logic [5:0] hit=0, prompt_valid=0, track_locked=6'b111111;
  logic [31:0] prompt_ms[6];
  logic signed [25:0] prompt[6];
  integer checked[6];
  integer ms;
  bit cfg_edge_checked=0;
  localparam logic [19:0] NH=20'b00000100110101001110;
  bds_bb_6ch_core dut (
    .clk(clk),.rst_n(rst_n),.IF(2'b10),.cfg_valid(cfg_valid),
    .cfg_channel(cfg_channel),.cfg_enable(cfg_enable),.cfg_prn(cfg_prn),
    .cfg_dop_min(-32'sd131200),.cfg_dop_step(32'sd131200),.cfg_bins(8'd3),
    .capture_ok(capture_ok),.bit_sync_ok(bit_sync_ok),.nav_data(nav_data),.nav_valid(nav_valid));
  function automatic bit data_bit(input integer channel, input integer bit_id);
    return ((bit_id*7+channel*3)%11)<5;
  endfunction
  for(genvar c=0;c<6;c++) begin:g_inject
    initial begin
      force dut.g_ch[c].u_channel.acq_ready=hit[c];
      force dut.g_ch[c].u_channel.acq_found=hit[c];
      force dut.g_ch[c].u_channel.ho_phase=48'd100;
      force dut.g_ch[c].u_channel.ho_carrier=32'd0;
      force dut.g_ch[c].u_channel.res_dop=32'sd0;
      force dut.g_ch[c].u_channel.dump_valid=prompt_valid[c];
      force dut.g_ch[c].u_channel.dump_partial=1'b0;
      force dut.g_ch[c].u_channel.dump_ms=prompt_ms[c];
      force dut.g_ch[c].u_channel.prompt_i=prompt[c];
      force dut.g_ch[c].u_channel.locked=track_locked[c];
    end
    always @(negedge clk) if(rst_n && nav_valid[c]) begin
      if(!capture_ok[c] || !bit_sync_ok[c]) $fatal(1,"invalid channel status %0d",c);
      if(nav_data[c] !== data_bit(c,int'(dut.g_ch[c].u_channel.u_nh.bit_ms)/20))
        $fatal(1,"navigation bit/channel mismatch channel %0d",c);
      checked[c]++;
    end
  end
  task automatic config_ch(input integer channel,input bit enabled,input integer prn);
    @(negedge clk); cfg_valid=1;cfg_channel=3'(channel);cfg_enable=enabled;cfg_prn=6'(prn);
    @(negedge clk); cfg_valid=0;
  endtask
  initial begin
    for(int c=0;c<6;c++) begin checked[c]=0;prompt[c]=0;prompt_ms[c]=0;end
    repeat(3) @(negedge clk);rst_n=1;
    if({capture_ok,bit_sync_ok,nav_valid}!==18'd0) $fatal(1,"reset status");
    for(int c=0;c<6;c++) config_ch(c,1,c+6);
    // Rewrite during PRN generation: old generation must drain before restart.
    config_ch(0,1,10);
    repeat(4200) @(negedge clk);
    for(int c=0;c<6;c++) begin
      hit[c]=1;
      repeat(3) @(negedge clk);
      if(capture_ok !== ((6'b000001<<(c+1))-1)) $fatal(1,"staggered acquisition/channel order");
    end
    config_ch(7,0,0);
    if(capture_ok!==6'b111111) $fatal(1,"invalid channel changed state");
    for(ms=0;ms<1200;ms++) begin
      if(ms==500) begin
        config_ch(2,0,0);
        if(capture_ok!==6'b111011 || bit_sync_ok[2] || nav_valid[2])
          $fatal(1,"channel disable was not isolated");
      end
      if(ms==550) config_ch(2,1,8);
      if(ms==800) begin
        track_locked[4]=0;
        repeat(3) @(negedge clk);
        if(capture_ok!==6'b101111 || bit_sync_ok[4] || nav_valid[4])
          $fatal(1,"loss of lock did not withdraw channel status");
      end
      if(ms==850) track_locked[4]=1;
      for(int c=0;c<6;c++) begin
        prompt_ms[c]=32'(ms+c*3);
        prompt[c]=(NH[19-((ms+c*3)%20)] ^ data_bit(c,(ms+c*3)/20)) ? -26'sd10000 : 26'sd10000;
      end
      prompt_valid=6'b111111;
      @(negedge clk); prompt_valid=0;
      repeat(60) @(negedge clk);
      if(ms>590 && (ms<800 || ms>850) && capture_ok!==6'b111111) $fatal(1,"reacquisition did not restore channel");
      if(capture_ok[5]!==1'b1 || capture_ok[3]!==1'b1 || capture_ok[1:0]!==2'b11)
        $fatal(1,"reconfiguration disturbed another channel");
      if((^{capture_ok,bit_sync_ok,nav_valid,nav_data})===1'bx) $fatal(1,"unexpected X/Z");
    end
    for(int c=0;c<6;c++) begin
      if(checked[c]<10) $fatal(1,"too few real NH navigation bits channel %0d count=%0d",c,checked[c]);
      $display("CHANNEL %0d NAV_BITS %0d",c,checked[c]);
    end
    // Present a synchronous configuration while an existing valid pulse is high.
    // Its effect belongs to the next rising edge, never to the arrival of cfg.
    fork
      begin
        wait(nav_valid[0]===1'b1);
        #1; cfg_valid=1;cfg_channel=0;cfg_enable=0;
        #1; if(!nav_valid[0]) $fatal(1,"configuration truncated nav_valid before clock edge");
        @(posedge clk);#1;
        if(nav_valid[0] || capture_ok[0] || bit_sync_ok[0]) $fatal(1,"configuration not applied at edge");
        cfg_edge_checked=1;
      end
      begin
        for(int extra=1200;extra<1240;extra++) begin
          for(int c=0;c<6;c++) begin
            prompt_ms[c]=32'(extra+c*3);
            prompt[c]=(NH[19-((extra+c*3)%20)] ^ data_bit(c,(extra+c*3)/20)) ? -26'sd10000 : 26'sd10000;
          end
          prompt_valid=6'b111111;
          @(negedge clk);prompt_valid=0;
          repeat(60) @(negedge clk);
        end
      end
    join_any
    disable fork;
    if(!cfg_edge_checked) $fatal(1,"no navigation pulse for configuration-edge check");
    $display("TEST PASSED");$finish;
  end
  initial begin #2000000;$fatal(1,"control test timeout");end
endmodule
