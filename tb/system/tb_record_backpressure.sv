`include "b1i_params.svh"
`include "b1i_records.svh"

module tb_record_backpressure;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic byte_valid = 0, byte_ready, cfg_valid = 0, rec_valid, rec_ready = 0;
  logic [7:0] data_byte = 8'h1B, cfg_addr = 0;
  logic [31:0] cfg_wdata = 0;
  wire [31:0] cfg_rdata;
  wire [255:0] rec_data;
  wire rec_last, error_valid;
  wire [31:0] error_code;
  b1i_rx_top #(.N_LANES(4), .BUF_DEPTH(256)) dut (
    .clk(clk), .rst_n(rst_n), .byte_valid(byte_valid), .data_byte(data_byte), .byte_ready(byte_ready),
    .sram_run(1'b0), .sram_pace_en(1'b0), .sram_pace_inc(32'd0), .sram_sample_total(32'd0),
    .sram_rd(), .sram_addr(), .sram_rdata(8'd0), .sram_rvalid(1'b0), .sram_done(),
    .cfg_valid(cfg_valid), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata), .cfg_ready(),
    .cfg_rdata(cfg_rdata), .rec_valid(rec_valid), .rec_ready(rec_ready), .rec_data(rec_data),
    .rec_last(rec_last), .ch_locked(), .ch_bit_valid(), .ch_nav_valid(),
    .error_valid(error_valid), .error_code(error_code));

  integer errors = 0, overflow_events = 0, accepted = 0, expected_epoch = 1;
  integer in_bundle = 0, bytes_sent = 0, nav_count = 0;
  logic [255:0] stalled_data;
  logic was_stalled = 0;
  always @(posedge clk) begin
    if (rst_n) begin
      if (error_valid) begin
        overflow_events++;
        if (error_code != ERR_FIFO_OVERFLOW) errors++;
      end
      if (was_stalled && (!rec_valid || rec_data !== stalled_data)) begin
        $display("FAIL: valid/data changed during backpressure"); errors++;
      end
      was_stalled = rec_valid && !rec_ready;
      stalled_data = rec_data;
      if (rec_valid && rec_ready) begin
        accepted++;
        if (rec_data[255:252] == REC_NAV) begin
          nav_count++;
          if (rec_data[247:242] != 39 || rec_data[241:238] != 3
              || rec_data[223:0] != 224'h12345) begin
            $display("FAIL: queued NAV changed identity/payload"); errors++;
          end
        end else if (in_bundle == 0) begin
          if (rec_data[255:252] != REC_EPOCH || rec_data[251:220] != expected_epoch
              || rec_data[219:188] != expected_epoch * 2 * SAMPLES_PER_MS) begin
            $display("FAIL: epoch header expected=%0d got=%h", expected_epoch, rec_data); errors++;
          end
          in_bundle = 1;
        end else begin
          if (rec_data[255:252] != REC_MEAS || rec_data[233:202] != expected_epoch
              || rec_data[251:248] != in_bundle - 1
              || rec_last != (in_bundle == 12) || $isunknown(rec_data)) begin
            $display("FAIL: MEAS order/content epoch=%0d ch=%0d got=%h",
                     expected_epoch, in_bundle - 1, rec_data); errors++;
          end
          if (in_bundle == 12) begin in_bundle = 0; expected_epoch++; end
          else in_bundle++;
        end
      end
    end
  end
  task automatic cfgw(input [7:0] a, input [31:0] d);
    @(negedge clk); cfg_valid = 1; cfg_addr = a; cfg_wdata = d;
    @(negedge clk); cfg_valid = 0;
  endtask
  initial begin
    repeat (4) @(negedge clk); rst_n = 1;
    cfgw(8'h01, 15);
    if (cfg_rdata != 12) begin $display("FAIL: n_prns clamp"); errors++; end
    cfgw(8'h01, 0);
    cfgw(8'h02, 32'h0000_3F0F); // Out-of-range list index must not create X.
    if ($isunknown(dut.prn_list)) begin $display("FAIL: PRN list corrupted"); errors++; end
    cfgw(8'h15, 0);
    if (cfg_rdata != 1) begin $display("FAIL: zero epoch clamp"); errors++; end
    cfgw(8'h15, 2); cfgw(8'h00, 1);
    cfgw(8'h20, 1); // Invalid PRN 0 must not hang or select force handover later.
    repeat (10) @(negedge clk);
    if (dut.force_pend || dut.gen_busy) begin $display("FAIL: invalid force request"); errors++; end
    // Three packets exceed the FIFO capacity; fourth packet must signal overrun
    // without overwriting the third packet's pending MEAS records.
    while (bytes_sent < 8 * (SAMPLES_PER_MS / 4)) begin
      @(negedge clk);
      byte_valid = byte_ready;
      if (byte_ready) bytes_sent++;
    end
    @(negedge clk); byte_valid = 0;
    repeat (100) @(negedge clk);
    if (overflow_events != 1) begin
      $display("FAIL: expected one dropped epoch event, got=%0d", overflow_events); errors++;
    end
    rec_ready = 1;
    repeat (100) @(negedge clk);
    if (accepted != 39 || expected_epoch != 4 || in_bundle != 0) begin
      $display("FAIL: record loss/duplication accepted=%0d epoch=%0d", accepted, expected_epoch); errors++;
    end
    // Queue a navigation record and then change the source before it is scheduled.
    force dut.ch_prn = 72'd39;
    force dut.ch_gen = 96'd3;
    force dut.sf_info = 2688'h12345;
    force dut.sf_valid = 12'd1;
    @(negedge clk);
    release dut.sf_valid;
    force dut.ch_prn = 72'd63;
    force dut.ch_gen = 96'd4;
    force dut.sf_info = 2688'hABCDEF;
    repeat (20) @(negedge clk);
    release dut.ch_prn; release dut.ch_gen; release dut.sf_info;
    if (nav_count != 1) begin $display("FAIL: missing/duplicate NAV"); errors++; end
    if (errors == 0) $display("TEST PASSED");
    else $display("TEST FAILED: %0d", errors);
    $finish;
  end
  initial begin #3000000; $display("TEST FAILED: timeout"); $finish; end
endmodule
