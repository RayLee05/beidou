// tb_d1_frame_sync.sv -- 帧同步 / 极性 / 去交织 / BCH 纠错 / 字段提取
//   输入 7 个子帧（第 3 个含单比特错误；第 5 个子帧前 40 bit 起整体反相）。
//   期望输出子帧 0,1,2,4,5（子帧 3 的后续前导码被反相打断，子帧 6 之后没有前导码）。
`include "b1i_params.svh"

module tb_d1_frame_sync;

  logic clk = 1'b0, rst_n;
  always #5 clk = ~clk;

  logic [0:0]   bits [0:4095];
  integer       n_bits, n_sf, flip_at;
  integer       exp_start [0:7];
  integer       exp_id [0:7];
  integer       exp_sow [0:7];
  logic [223:0] exp_info [0:7];
  integer       want [0:4] = '{0, 1, 2, 4, 5};

  logic          bit_valid, bit_val;
  logic [31:0]   bit_ms;
  logic          sf_valid, sf_inverted, frame_synced, anchor_valid, week_valid;
  logic [2:0]    sf_id;
  logic [19:0]   sf_sow, anchor_sow;
  logic [31:0]   sf_start_ms, anchor_ms;
  logic [223:0]  sf_info;
  logic [4:0]    sf_fixes;
  logic [12:0]   week;
  logic [63:0] bit_end_sample;
  logic [47:0] bit_end_phase;
  logic [299:0] sf_raw;
  logic [9:0][1:0] sf_word_fixes;
  logic [9:0][63:0] sf_word_samples;
  logic [9:0][47:0] sf_word_phases;
  logic [9:0][31:0] sf_word_ms;
  function automatic logic [63:0] tag_sample(input integer idx);
    return 64'd100000 + 64'(idx)*64'd327360 + 64'(idx%7)*64'd10;
  endfunction
  function automatic logic [47:0] tag_phase(input integer idx);
    return {11'(idx%2046), 37'(idx*134713)};
  endfunction

  d1_frame_sync #(.WITH_METADATA(1'b1)) dut (
    .clk(clk), .rst_n(rst_n), .clear(1'b0), .bit_valid(bit_valid), .bit_val(bit_val),
    .bit_ms(bit_ms), .sf_valid(sf_valid), .sf_id(sf_id), .sf_sow(sf_sow),
    .bit_end_sample(bit_end_sample), .bit_end_phase(bit_end_phase),
    .sf_raw(sf_raw), .sf_word_fixes(sf_word_fixes), .sf_word_samples(sf_word_samples),
    .sf_word_phases(sf_word_phases), .sf_word_ms(sf_word_ms),
    .sf_start_ms(sf_start_ms), .sf_info(sf_info), .sf_fixes(sf_fixes),
    .sf_inverted(sf_inverted), .frame_synced(frame_synced), .anchor_valid(anchor_valid),
    .anchor_ms(anchor_ms), .anchor_sow(anchor_sow), .week(week), .week_valid(week_valid),
    .sf_err());

  localparam int MS0 = 1000;     // 第 0 个比特的 ms 标签
  integer errors = 0, got = 0, e, total_fixes = 0;
  logic finish=0, public_valid, public_overflow;
  logic [255:0] public_data;
  logic [63:0] processed_samples=0;
  integer nav_fd, public_count=0, end_count=0;
  public_record_encoder u_export (
    .clk(clk), .rst_n(rst_n), .sample_count(processed_samples), .hardware_cycles(64'd123456),
    .finish(finish), .input_error(1'b0), .missing_ticks(64'd0), .input_ready(),
    .record_valid(public_valid), .record_ready(1'b1), .record_data(public_data), .overflow(public_overflow),
    .epoch_valid(1'b0), .epoch_id(32'd0), .active(12'd1), .locked(12'd1), .nh_valid(12'd1),
    .frame_valid({11'd0,frame_synced}), .time_valid({11'd0,anchor_valid}),
    .prn({66'd0,6'd63}), .generation({88'd0,8'd7}),
    .dump_valid('0), .dump_partial('0), .code_wrap('0), .code_ms('0), .dop_word('0),
    .code_phase('0), .code_after_sample('0), .carrier_phase('0), .prompt_i('0), .prompt_q('0),
    .anchor_sow('0), .sf_valid({11'd0,sf_valid}), .sf_id({33'd0,sf_id}), .sf_sow({220'd0,sf_sow}),
    .sf_info({2464'd0,sf_info}), .sf_raw({3300'd0,sf_raw}),
    .sf_word_fixes({220'd0,sf_word_fixes}), .sf_word_samples({7040'd0,sf_word_samples}),
    .sf_word_phases({5280'd0,sf_word_phases}), .sf_word_ms({3520'd0,sf_word_ms}),
    .acq_start(1'b0), .acq_done(1'b0), .acq_found(1'b0), .acq_prn(6'd0),
    .acq_lag_halfchip(12'd0), .acq_dop_word(32'd0), .acq_peak(28'd0),
    .ev_valid(1'b0), .ev_code(4'd0), .ev_ch(4'd0), .ev_prn(6'd0), .ev_generation(8'd0));
  always @(posedge clk) if (rst_n && public_valid) begin
    if (end_count!=0) $fatal(1,"record after END");
    for (int b=0; b<32; b++) $fwrite(nav_fd,"%c",public_data[8*b+:8]);
    if (public_data[7:0]==2) public_count++;
    else if (public_data[7:0]==6) end_count++;
    else $fatal(1,"unexpected navigation exporter record");
  end

  always @(posedge clk) begin
    if (sf_valid) begin
      if (got >= 5) begin
        $display("ERROR: unexpected extra subframe id=%0d", sf_id);
        errors++;
      end else begin
        e = want[got];
        $display("subframe: id=%0d sow=%0d start_ms=%0d fixes=%0d inverted=%0d", sf_id, sf_sow,
                 sf_start_ms, sf_fixes, sf_inverted);
        if (sf_id != exp_id[e] || sf_sow != exp_sow[e]) begin
          $display("ERROR: id/sow mismatch, want %0d/%0d", exp_id[e], exp_sow[e]); errors++;
        end
        if (sf_start_ms != MS0 + 20 * exp_start[e]) begin
          $display("ERROR: start_ms want %0d", MS0 + 20 * exp_start[e]); errors++;
        end
        if (sf_info !== exp_info[e]) begin
          $display("ERROR: info mismatch"); errors++;
        end
        if (sf_inverted != (exp_start[e] >= flip_at)) begin
          $display("ERROR: polarity"); errors++;
        end
        total_fixes += sf_fixes;
        begin
          integer idx, fixes_sum;
          fixes_sum = 0;
          for (int w = 0; w < 10; w++) begin
            idx = exp_start[e] + 29 + 30*w;
            if (sf_word_samples[w] !== tag_sample(idx) || sf_word_phases[w] !== tag_phase(idx)
                || sf_word_ms[w] !== 32'(MS0 + 20*(idx+1))) begin
              $display("ERROR: word %0d END metadata idx=%0d sample=%0d", w+1, idx, sf_word_samples[w]);
              errors++;
            end
            fixes_sum += sf_word_fixes[w];
            for (int b = 0; b < 30; b++) begin
              idx = exp_start[e] + 30*w + b;
              if (sf_raw[299-30*w-b] !== (bits[idx][0] ^ sf_inverted)) begin
                $display("ERROR: raw word bit %0d", idx); errors++;
              end
            end
          end
          if (fixes_sum != sf_fixes) begin $display("ERROR: per-word BCH counts"); errors++; end
        end
      end
      got++;
    end
  end

  integer fd, rc, i;
  initial begin
    nav_fd=$fopen("reports/sim/public_navigation.bin","wb");
    if (nav_fd==0) $fatal(1,"navigation output file");
    $readmemh("tb/vectors/nav_bits.hex", bits);
    fd = $fopen("tb/vectors/nav_expected.txt", "r");
    rc = $fscanf(fd, "%d %d %d\n", n_bits, n_sf, flip_at);
    for (i = 0; i < n_sf; i++)
      rc = $fscanf(fd, "%d %d %d %h\n", exp_start[i], exp_id[i], exp_sow[i], exp_info[i]);
    $fclose(fd);

    rst_n = 1'b0; bit_valid = 0; bit_val = 0; bit_ms = 0; bit_end_sample = 0; bit_end_phase = 0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    for (i = 0; i < n_bits; i++) begin
      repeat (30) @(negedge clk);
      bit_valid = 1; bit_val = bits[i][0]; bit_ms = MS0 + 20 * i;
      bit_end_sample = tag_sample(i); bit_end_phase = tag_phase(i);
      processed_samples=tag_sample(i);
      @(negedge clk);
      bit_valid = 0;
    end
    repeat (100) @(negedge clk);
    finish=1;
    repeat (100) @(negedge clk);
    $fclose(nav_fd);
    if (public_count!=50 || end_count!=1 || public_overflow) $fatal(1,"navigation export count");
    $display("%0d subframes, total BCH fixes %0d, week=%0d valid=%0d", got, total_fixes, week,
             week_valid);
    if (got != 5) begin $display("ERROR: expected 5 subframes"); errors++; end
    if (total_fixes < 1) begin $display("ERROR: injected bit error not corrected"); errors++; end
    if (!week_valid || week != 950) begin $display("ERROR: week"); errors++; end
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d", errors);
    $finish;
  end

endmodule
