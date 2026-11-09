`timescale 1ns/1ps
module tb_probe;
  reg clk=0,rst_n=0,data=0;
  supply1 high_rail;
  supply0 low_rail;
  wire result;
  reg expected;
  always #30.5474095 clk=~clk;
  bds_pad_probe dut(.clk(clk),.rst_n(rst_n),.data(data),.result(result),
    .VDD(high_rail),.VDDPST(high_rail),.POC(high_rail),.VSS(low_rail),.VSSPST(low_rail));
  initial begin
    if($test$plusargs("MIN"))
      $sdf_annotate("output/probe.sdf",dut,,"logs/probe_sdf_min.log","MINIMUM");
    else
      $sdf_annotate("output/probe.sdf",dut,,"logs/probe_sdf_max.log","MAXIMUM");
    repeat(3) @(negedge clk);rst_n=1;
    for(int i=0;i<64;i++) begin
      @(posedge clk);#2;data=((i*7)%11)<5;expected=data;
      // Receiver samples at the following external clock after the capture
      // cycle. This is the SDC synchronous output setup/hold contract.
      repeat(2) @(posedge clk);
      if(result!==expected) $fatal(1,"PAD GLS data/X mismatch cycle %0d",i);
    end
    $display("TEST PASSED: powered PAD + standard-cell SDF %s",$test$plusargs("MIN")?"MIN":"MAX");
    $finish;
  end
  initial begin #30000;$fatal(1,"probe GLS timeout");end
endmodule
