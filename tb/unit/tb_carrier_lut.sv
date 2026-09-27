// tb_carrier_lut.sv -- 载波查表单元测试（定向）
`include "b1i_params.svh"

module tb_carrier_lut;

  logic [NCO_PHASE_W-1:0]            phase;
  logic signed [CARR_LUT_DATA_W-1:0] cos_v, sin_v;
  integer errors;

  carrier_lut dut (.phase(phase), .cos_v(cos_v), .sin_v(sin_v));

  task automatic check(input [NCO_PHASE_W-1:0] ph,
                       input signed [CARR_LUT_DATA_W-1:0] ec,
                       input signed [CARR_LUT_DATA_W-1:0] es,
                       input [8*40:1] name);
    begin
      phase = ph; #1;
      if (cos_v !== ec || sin_v !== es) begin
        $display("FAIL %0s: phase=%0d cos=%0d(exp %0d) sin=%0d(exp %0d)",
                 name, ph, cos_v, ec, sin_v, es);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    errors = 0;
    // 相位 = k * 2^30 对应 0 / 90 / 180 / 270 度
    phase = 32'd0;                 #1;
    check(32'd0,           10'sd511,  10'sd0,    "0deg");
    check(32'd1073741824,  10'sd0,    10'sd511,  "90deg");
    check(32'd2147483648, -10'sd511,  10'sd0,    "180deg");
    check(32'd3221225472,  10'sd0,   -10'sd511,  "270deg");
    // 表值必须落在 10 bit 有符号范围
    check(32'd536870912,   10'sd361,  10'sd361,  "45deg(a=511*cos45=361)");

    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d 处不一致", errors);
    $finish;
  end

endmodule
