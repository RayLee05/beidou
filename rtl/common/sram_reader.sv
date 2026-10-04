// =============================================================================
// sram_reader.sv -- SRAM 样本读取与本地采样节拍
//   SRAM 读口：sram_rd/sram_addr 发起读，RD_LAT 拍后数据有效（或用 sram_rvalid）。
//   字宽 WORD_W（8 的倍数），每字节 4 个样本，字节内早样本在 [7:6]；
//   BYTE_ORDER=0 时字内高字节为早字节，=1 时低字节为早字节。
//   节拍：pace_en=1 时按 pace_inc（= Fs/f_clk * 2^32）累加产生样本节拍，模拟实时；
//         pace_en=0 时数据就绪即输出（每拍最多一个样本），用于加速仿真。
//   读满 sample_total 个样本后停止并置 done（输入结束，与失锁区分）。
//   需求: REQ-IN-001..004（指导书 1.4 节）
// =============================================================================
`include "b1i_params.svh"

module sram_reader #(
  parameter int WORD_W     = 8,
  parameter int ADDR_W     = 24,
  parameter int RD_LAT     = 1,
  parameter int BYTE_ORDER = 0,
  parameter bit USE_RVALID = 1'b0
) (
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic                       run,
  input  logic                       pace_en,
  input  logic [31:0]                pace_inc,
  input  logic [31:0]                sample_total,
  // SRAM
  output logic                       sram_rd,
  output logic [ADDR_W-1:0]          sram_addr,
  input  logic [WORD_W-1:0]          sram_rdata,
  input  logic                       sram_rvalid,
  // 样本
  output logic                       sample_valid,
  output logic signed [SAMPLE_W-1:0] sample,
  output logic [31:0]                sample_count,
  output logic                       done
);

  localparam int SPW   = WORD_W / 2;                 // 每字样本数
  localparam int FIFO_D = 4;

  // ---------------------------------------------------------------- 读请求与固定延迟
  logic [RD_LAT-1:0] lat_pipe;
  logic              rvalid;
  logic [2:0]        inflight, fifo_cnt;
  logic [31:0]       words_req, words_need;

  assign words_need = (sample_total + 32'(SPW - 1)) / 32'(SPW);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) lat_pipe <= '0;
    else        lat_pipe <= (RD_LAT == 1) ? RD_LAT'(sram_rd) : {lat_pipe[RD_LAT-2:0], sram_rd};
  end
  assign rvalid = USE_RVALID ? sram_rvalid : lat_pipe[RD_LAT-1];

  wire can_req = run && (words_req < words_need) && (32'(inflight) + 32'(fifo_cnt) < FIFO_D);
  assign sram_rd   = can_req;
  assign sram_addr = ADDR_W'(words_req);

  // ---------------------------------------------------------------- 字 FIFO
  logic [WORD_W-1:0] fifo [FIFO_D];
  logic [1:0]        wp, rp;
  logic              pop;

  // ---------------------------------------------------------------- 解包
  logic [WORD_W-1:0] cur;
  logic [$clog2(SPW+1)-1:0] left;
  logic [32:0]       acc;
  logic [1:0]        credit;

  wire want_tick = pace_en ? (credit != 0) : 1'b1;
  wire emit = run && (left != 0) && want_tick && (sample_count < sample_total);
  assign pop = run && (left == 0 || (emit && left == 1)) && (fifo_cnt != 0);

  // 当前字中下一个样本的 2 bit 码
  logic [1:0] code;
  always_comb begin
    if (BYTE_ORDER == 0) code = cur[WORD_W-1 -: 2];
    else                 code = cur[7:6];
  end

  always_comb begin
    case (code)
      2'b00:   sample = -3;
      2'b01:   sample = -1;
      2'b10:   sample = 1;
      default: sample = 3;
    endcase
  end
  assign sample_valid = emit;
  assign done = run && (sample_count >= sample_total);

  // 取走一个样本后的字：BYTE_ORDER=0 整字左移 2；
  // BYTE_ORDER=1 在最低字节内左移 2，该字节的第 4 个样本取走后整字右移 8 换到下一字节
  function automatic logic [WORD_W-1:0] shift_word(input logic [WORD_W-1:0] w,
                                                   input int unsigned used);
    if (BYTE_ORDER == 0)  return w << 2;
    if ((used % 4) == 3)  return w >> 8;
    return {w[WORD_W-1:8], w[5:0], 2'b00};
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      inflight <= '0; fifo_cnt <= '0; words_req <= '0; wp <= '0; rp <= '0;
      cur <= '0; left <= '0; acc <= '0; credit <= '0; sample_count <= '0;
    end else if (!run) begin
      inflight <= '0; fifo_cnt <= '0; words_req <= '0; wp <= '0; rp <= '0;
      left <= '0; acc <= '0; credit <= '0; sample_count <= '0;
    end else begin
      // 请求与返回
      if (can_req) words_req <= words_req + 32'd1;
      inflight <= inflight + (can_req ? 3'd1 : 3'd0) - (rvalid ? 3'd1 : 3'd0);
      if (rvalid) begin
        fifo[wp] <= sram_rdata;
        wp <= wp + 2'd1;
      end
      fifo_cnt <= fifo_cnt + (rvalid ? 3'd1 : 3'd0) - (pop ? 3'd1 : 3'd0);

      // 节拍
      acc <= {1'b0, acc[31:0]} + {1'b0, pace_inc};
      credit <= credit + ((acc[32] && credit != 2'd3) ? 2'd1 : 2'd0)
                       - ((emit && pace_en) ? 2'd1 : 2'd0);

      // 样本输出
      if (pop) begin
        cur  <= fifo[rp];
        rp   <= rp + 2'd1;
        left <= SPW[$clog2(SPW+1)-1:0];
      end else if (emit) begin
        cur  <= shift_word(cur, SPW - left);
        left <= left - 1'b1;
      end
      if (emit) sample_count <= sample_count + 32'd1;
    end
  end

endmodule
