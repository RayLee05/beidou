// =============================================================================
// prn_code_gen.sv -- B1I 测距码发生器（ICD 2.1 图 4-1 / 表 4-2）
//   start 后连续 2046 拍输出码片（out_we/out_addr/out_chip），直接接码 RAM 写口。
//   G1 反馈 = 级 1^7^8^9^10^11，输出级 11；G2 反馈 = 级 1^2^3^4^5^8^9^11，
//   输出取表 4-2 两个相位选择抽头之异或；初相均为 01010101010（级 1..11）。
//   PRN 不在表内（0 或 >37）时 bad_prn 置位且不输出。
//   逐位参考：sw/b1i_ref/prn_b1i.py
//   需求: REQ-SIG-006
// =============================================================================
`include "b1i_params.svh"

module prn_code_gen (
  input  logic             clk,
  input  logic             rst_n,
  input  logic             start,
  input  logic [PRN_W-1:0] prn,
  output logic             busy,
  output logic             done,       // 最后一个码片写出后的下一拍，单拍
  output logic             bad_prn,
  output logic             out_we,
  output logic [10:0]      out_addr,
  output logic             out_chip
);

  localparam logic [11:1] INIT = 11'b01010101010;   // 级 11..1（回文）

  logic [11:1] g1, g2;
  logic [3:0]  ta, tb;
  logic [10:0] cnt;
  logic        run;

  // ICD 表 4-2：PRN -> 相位选择抽头（级号）
  function automatic logic [7:0] taps(input logic [PRN_W-1:0] p);
    case (p)
      6'd1:  taps = {4'd1, 4'd3};   6'd2:  taps = {4'd1, 4'd4};   6'd3:  taps = {4'd1, 4'd5};
      6'd4:  taps = {4'd1, 4'd6};   6'd5:  taps = {4'd1, 4'd8};   6'd6:  taps = {4'd1, 4'd9};
      6'd7:  taps = {4'd1, 4'd10};  6'd8:  taps = {4'd1, 4'd11};  6'd9:  taps = {4'd2, 4'd7};
      6'd10: taps = {4'd3, 4'd4};   6'd11: taps = {4'd3, 4'd5};   6'd12: taps = {4'd3, 4'd6};
      6'd13: taps = {4'd3, 4'd8};   6'd14: taps = {4'd3, 4'd9};   6'd15: taps = {4'd3, 4'd10};
      6'd16: taps = {4'd3, 4'd11};  6'd17: taps = {4'd4, 4'd5};   6'd18: taps = {4'd4, 4'd6};
      6'd19: taps = {4'd4, 4'd8};   6'd20: taps = {4'd4, 4'd9};   6'd21: taps = {4'd4, 4'd10};
      6'd22: taps = {4'd4, 4'd11};  6'd23: taps = {4'd5, 4'd6};   6'd24: taps = {4'd5, 4'd8};
      6'd25: taps = {4'd5, 4'd9};   6'd26: taps = {4'd5, 4'd10};  6'd27: taps = {4'd5, 4'd11};
      6'd28: taps = {4'd6, 4'd8};   6'd29: taps = {4'd6, 4'd9};   6'd30: taps = {4'd6, 4'd10};
      6'd31: taps = {4'd6, 4'd11};  6'd32: taps = {4'd8, 4'd9};   6'd33: taps = {4'd8, 4'd10};
      6'd34: taps = {4'd8, 4'd11};  6'd35: taps = {4'd9, 4'd10};  6'd36: taps = {4'd9, 4'd11};
      6'd37: taps = {4'd10, 4'd11};
      default: taps = 8'd0;
    endcase
  endfunction

  wire fb1 = g1[1] ^ g1[7] ^ g1[8] ^ g1[9] ^ g1[10] ^ g1[11];
  wire fb2 = g2[1] ^ g2[2] ^ g2[3] ^ g2[4] ^ g2[5] ^ g2[8] ^ g2[9] ^ g2[11];

  assign busy     = run;
  assign out_we   = run;
  assign out_addr = cnt;
  assign out_chip = g1[11] ^ g2[ta] ^ g2[tb];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      g1 <= INIT; g2 <= INIT; ta <= 4'd1; tb <= 4'd1;
      cnt <= '0; run <= 1'b0; done <= 1'b0; bad_prn <= 1'b0;
    end else begin
      done <= 1'b0;
      if (start && !run) begin
        g1 <= INIT;
        g2 <= INIT;
        {ta, tb} <= taps(prn);
        cnt <= '0;
        bad_prn <= (taps(prn) == 8'd0);
        run <= (taps(prn) != 8'd0);
      end else if (run) begin
        g1 <= {g1[10:1], fb1};
        g2 <= {g2[10:1], fb2};
        if (cnt == 11'(CODE_CHIPS_PER_PERIOD - 1)) begin
          run  <= 1'b0;
          done <= 1'b1;
        end
        cnt <= cnt + 11'd1;
      end
    end
  end

endmodule
