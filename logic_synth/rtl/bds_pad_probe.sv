module bds_pad_probe(inout wire POC,VDD,VSS,VDDPST,VSSPST,input wire clk,rst_n,data,output wire result);
  wire c,r,d,q;
  reg value;
  PDDW04SDGZ_H_G pclk (.I(1'b0),.OEN(1'b1),.REN(1'b1),.PAD(clk),.C(c),.POC(POC),.VDD(VDD),.VSS(VSS),.VDDPST(VDDPST),.VSSPST(VSSPST));
  PDDW04SDGZ_H_G prst (.I(1'b0),.OEN(1'b1),.REN(1'b1),.PAD(rst_n),.C(r),.POC(POC),.VDD(VDD),.VSS(VSS),.VDDPST(VDDPST),.VSSPST(VSSPST));
  PDDW04SDGZ_H_G pdat (.I(1'b0),.OEN(1'b1),.REN(1'b1),.PAD(data),.C(d),.POC(POC),.VDD(VDD),.VSS(VSS),.VDDPST(VDDPST),.VSSPST(VSSPST));
  always @(posedge c or negedge r) if(!r)value<=0;else value<=d;
  PDDW04SDGZ_H_G pout (.I(value),.OEN(1'b0),.REN(1'b1),.PAD(result),.C(),.POC(POC),.VDD(VDD),.VSS(VSS),.VDDPST(VDDPST),.VSSPST(VSSPST));
endmodule
