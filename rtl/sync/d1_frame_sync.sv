// =============================================================================
// d1_frame_sync.sv -- D1 帧同步、极性判定、去交织与 BCH(15,11,1) 纠错（每通道一份）
//   保存最近 311 个比特 sr（sr[0] 最新）。若 sr[310:300] 与 sr[10:0] 同为前导码
//   11100010010（或同为其反码），则 sr[310:11] 是一个完整子帧，极性随之确定。
//   译码：字 1 前 15 bit 不编码、后 15 bit 为一个码字；字 2-10 奇数位为码字 1、
//   偶数位为码字 2（ICD 第 19 页）。BCH 除法电路与纠错表按 ICD 图 5-4 / 表 5-2。
//   输出：224 bit 信息位（info[223] 为首个信息位）、FraID、SOW、子帧起点 ms 标签；
//   FraID 不在 1..5 的候选丢弃。最新有效子帧建立时间锚点 (anchor_ms, anchor_sow)。
//   逐位参考：sw/b1i_ref/d1_nav.py / prn_b1i.py
//   需求: REQ-SYN-004/005/006, REQ-NAV-001/002
// =============================================================================
`include "b1i_params.svh"

module d1_frame_sync #(parameter bit WITH_METADATA = 1'b0) (
  input  logic          clk,
  input  logic          rst_n,
  input  logic          clear,
  input  logic          bit_valid,
  input  logic          bit_val,
  input  logic [31:0]   bit_ms,         // 该比特第一个码周期的 ms 标签
  input  logic [63:0]   bit_end_sample,
  input  logic [47:0]   bit_end_phase,
  output logic          sf_valid,       // 单拍：一个子帧译码完成
  output logic [2:0]    sf_id,
  output logic [19:0]   sf_sow,
  output logic [31:0]   sf_start_ms,
  output logic [223:0]  sf_info,
  output logic [4:0]    sf_fixes,
  output logic [299:0]  sf_raw,
  output logic [9:0][1:0] sf_word_fixes,
  output logic [9:0][63:0] sf_word_samples,
  output logic [9:0][47:0] sf_word_phases,
  output logic [9:0][31:0] sf_word_ms,
  output logic          sf_inverted,
  output logic          frame_synced,   // 已获得至少一个有效子帧
  output logic          anchor_valid,
  output logic [31:0]   anchor_ms,
  output logic [19:0]   anchor_sow,
  output logic [12:0]   week,
  output logic          week_valid,
  output logic          sf_err           // 单拍：候选子帧因 BCH/字段失败丢弃
);

  localparam logic [10:0] PRE = 11'b11100010010;

  logic [310:0] sr;
  logic [8:0]   nbits;
  logic [299:0] sfb;            // 极性已校正；sfb[299] 为子帧第 1 个比特
  logic [31:0]  start_ms_q;
  logic         inv_q;
  logic         dec;
  logic [4:0]   cw;             // 码字序号 0..18
  logic [223:0] info;
  logic [8:0]   ipos;           // 下一个信息位写入位置（从 223 递减）
  logic [4:0]   fixes;
  logic         bch_bad;
  logic [9:0][1:0] word_fixes;
  logic [3:0] word_idx;

  // Circular history keeps each bit's measured END time. The next preamble
  // arrives 11 bits after the subframe, so its current NCO state is too late.
  // Capture the ten word-end entries during BCH decoding, before accepting
  // another candidate. No reset of the RAM is needed: nbits guards all reads.
  generate if (WITH_METADATA) begin : g_metadata
    logic [143:0] tags [0:310];
    logic [8:0] write_ptr, candidate_ptr;
    integer read_ptr;
    always_comb begin
      read_ptr = int'(candidate_ptr) - (281 - 30 * int'(word_idx));
      if (read_ptr < 0) read_ptr = read_ptr + 311;
    end
    always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        write_ptr <= '0; candidate_ptr <= '0;
        sf_word_samples <= '0; sf_word_phases <= '0; sf_word_ms <= '0;
      end else if (clear) begin
        write_ptr <= '0; candidate_ptr <= '0;
        sf_word_samples <= '0; sf_word_phases <= '0; sf_word_ms <= '0;
      end else begin
        if (bit_valid) begin
          tags[write_ptr] <= {bit_end_sample, bit_end_phase, bit_ms + 32'd20};
          write_ptr <= (write_ptr == 9'd310) ? 9'd0 : write_ptr + 9'd1;
          if (nbits >= 9'd310 && !dec &&
              ((sr[309:299] == PRE && {sr[9:0], bit_val} == PRE) ||
               (sr[309:299] == ~PRE && {sr[9:0], bit_val} == ~PRE)))
            candidate_ptr <= write_ptr;
        end else if (dec) begin
          {sf_word_samples[word_idx], sf_word_phases[word_idx], sf_word_ms[word_idx]}
            <= tags[read_ptr];
        end
      end
    end
  end else begin : g_no_metadata
    assign sf_word_samples = '0;
    assign sf_word_phases = '0;
    assign sf_word_ms = '0;
  end endgenerate

  // ---------------------------------------------------------------- BCH 译码（组合）
  function automatic logic [3:0] bch_syn(input logic [14:0] c);   // c[14] 为第 1 个比特
    logic [3:0] d;   // d[3]=D3 .. d[0]=D0
    d = 4'd0;
    for (int i = 14; i >= 0; i--) d = {d[2], d[1], d[0] ^ d[3], c[i] ^ d[3]};
    return d;
  endfunction

  function automatic logic [3:0] bch_par(input logic [14:0] cw);
    // 对 cw[14:4] 11 个信息位按图 5-2 编码，返回 D3D2D1D0
    logic [3:0] d;
    logic       fb;
    d = 4'd0;
    for (int i = 14; i >= 4; i--) begin
      fb = cw[i] ^ d[3];
      d  = {d[2], d[1], d[0] ^ fb, fb};
    end
    return d;
  endfunction

  function automatic logic [14:0] bch_rom(input logic [3:0] s);   // 表 5-2，左为第 1 个比特
    case (s)
      4'b0000: bch_rom = 15'b000000000000000;  4'b0001: bch_rom = 15'b000000000000001;
      4'b0010: bch_rom = 15'b000000000000010;  4'b0011: bch_rom = 15'b000000000010000;
      4'b0100: bch_rom = 15'b000000000000100;  4'b0101: bch_rom = 15'b000000100000000;
      4'b0110: bch_rom = 15'b000000000100000;  4'b0111: bch_rom = 15'b000010000000000;
      4'b1000: bch_rom = 15'b000000000001000;  4'b1001: bch_rom = 15'b100000000000000;
      4'b1010: bch_rom = 15'b000001000000000;  4'b1011: bch_rom = 15'b000000010000000;
      4'b1100: bch_rom = 15'b000000001000000;  4'b1101: bch_rom = 15'b010000000000000;
      4'b1110: bch_rom = 15'b000100000000000;  default: bch_rom = 15'b001000000000000;
    endcase
  endfunction

  // 当前码字：cw=0 为字 1 的码字；cw=2w-1 / 2w 为字 w+1（w=1..9）的码字 1 / 码字 2
  logic [29:0] word;
  logic [14:0] cword;
  always_comb begin
    word_idx = (cw == 5'd0 || cw >= 5'd19) ? 4'd0 : 4'((cw + 5'd1) >> 1);
    word = sfb[299 - 30 * word_idx -: 30];             // word[29] 为该字第 1 个比特
    if (cw == 5'd0) begin
      cword = word[14:0];
    end else begin
      for (int i = 0; i < 15; i++)
        cword[14 - i] = cw[0] ? word[29 - 2 * i] : word[28 - 2 * i];
    end
  end
  wire [3:0]  syn   = bch_syn(cword);
  wire [14:0] fixed = cword ^ bch_rom(syn);
  wire        bch_ok = (bch_par(fixed) == fixed[3:0]);

  // 信息位中的字段（info[223-i] 为第 i 个信息位，与 d1_nav.info_positions() 一致）
  wire [2:0]  f_fraid = info[223 - 15 -: 3];
  wire [19:0] f_sow   = {info[223 - 18 -: 8], info[223 - 26 -: 12]};
  wire [12:0] f_wn    = info[223 - 48 -: 13];          // 子帧 1 字 3 的前 13 bit

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sr <= '0; nbits <= '0; sfb <= '0; start_ms_q <= '0; inv_q <= 1'b0;
      dec <= 1'b0; cw <= '0; info <= '0; ipos <= '0; fixes <= '0; bch_bad <= 1'b0;
      word_fixes <= '0; sf_raw <= '0; sf_word_fixes <= '0;
      sf_valid <= 1'b0; sf_err <= 1'b0; sf_id <= '0; sf_sow <= '0; sf_start_ms <= '0; sf_info <= '0;
      sf_fixes <= '0; sf_inverted <= 1'b0; frame_synced <= 1'b0;
      anchor_valid <= 1'b0; anchor_ms <= '0; anchor_sow <= '0; week <= '0; week_valid <= 1'b0;
    end else if (clear) begin
      // 取消译码与字段检查；cw=19 也不能在下一拍提交旧通道的子帧。
      sr <= '0; nbits <= '0; sfb <= '0; start_ms_q <= '0; inv_q <= 1'b0;
      dec <= 1'b0; cw <= '0; info <= '0; ipos <= '0; fixes <= '0; bch_bad <= 1'b0;
      word_fixes <= '0; sf_raw <= '0; sf_word_fixes <= '0;
      sf_valid <= 1'b0; sf_err <= 1'b0; sf_id <= '0; sf_sow <= '0; sf_start_ms <= '0; sf_info <= '0;
      sf_fixes <= '0; sf_inverted <= 1'b0; frame_synced <= 1'b0;
      anchor_valid <= 1'b0; anchor_ms <= '0; anchor_sow <= '0; week <= '0; week_valid <= 1'b0;
    end else begin
      sf_valid <= 1'b0;
      sf_err   <= 1'b0;
      if (bit_valid) begin
        sr    <= {sr[309:0], bit_val};
        nbits <= (nbits == 9'd311) ? nbits : nbits + 9'd1;
        // 用移位后的内容判前导码：新比特成为 sr[0]
        if (nbits >= 9'd310 && !dec) begin
          if ((sr[309:299] == PRE) && ({sr[9:0], bit_val} == PRE)) begin
            sfb <= sr[309:10]; inv_q <= 1'b0;
            start_ms_q <= bit_ms - 32'd6200;           // 310 个比特之前
            dec <= 1'b1; cw <= '0; ipos <= 9'd223; fixes <= '0; bch_bad <= 1'b0;
            word_fixes <= '0;
          end else if ((sr[309:299] == ~PRE) && ({sr[9:0], bit_val} == ~PRE)) begin
            sfb <= ~sr[309:10]; inv_q <= 1'b1;
            start_ms_q <= bit_ms - 32'd6200;
            dec <= 1'b1; cw <= '0; ipos <= 9'd223; fixes <= '0; bch_bad <= 1'b0;
            word_fixes <= '0;
          end
        end
      end else if (dec) begin
        // 每拍译一个码字，写入信息位
        if (cw == 5'd0) begin
          info[223 -: 15] <= word[29:15];
          info[208 -: 11] <= fixed[14:4];
          ipos <= 9'd197;
        end else begin
          info[ipos -: 11] <= fixed[14:4];
          ipos <= ipos - 9'd11;
        end
        if (syn != 4'd0) begin
          fixes <= fixes + 5'd1;
          word_fixes[word_idx] <= word_fixes[word_idx] + 2'd1;
        end
        if (!bch_ok) bch_bad <= 1'b1;
        if (cw == 5'd18) begin
          dec <= 1'b0;
          cw  <= 5'd19;                                 // 下一拍做字段检查
        end else begin
          cw <= cw + 5'd1;
        end
      end else if (cw == 5'd19) begin
        cw <= '0;
        if (!bch_bad && f_fraid >= 3'd1 && f_fraid <= 3'd5 && f_sow < 20'd604800) begin
          sf_valid     <= 1'b1;
          sf_id        <= f_fraid;
          sf_sow       <= f_sow;
          sf_start_ms  <= start_ms_q;
          sf_info      <= info;
          sf_fixes     <= fixes;
          sf_raw       <= sfb;
          sf_word_fixes <= word_fixes;
          sf_inverted  <= inv_q;
          frame_synced <= 1'b1;
          anchor_valid <= 1'b1;
          anchor_ms    <= start_ms_q;
          anchor_sow   <= f_sow;
          if (f_fraid == 3'd1) begin
            week <= f_wn;
            week_valid <= 1'b1;
          end
        end else begin
          sf_err <= 1'b1;
        end
      end
    end
  end

endmodule
