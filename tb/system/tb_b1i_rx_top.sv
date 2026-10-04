// tb_b1i_rx_top.sv -- 顶层冒烟：强制装载 + 短输入，检查记录流出
`include "b1i_params.svh"
`include "b1i_records.svh"

module tb_b1i_rx_top;

  logic clk = 1'b0, rst_n;
  always #5 clk = ~clk;

  logic        byte_valid, byte_ready, cfg_valid, rec_valid, rec_ready;
  logic [7:0]  data_byte, cfg_addr;
  logic [31:0] cfg_wdata, cfg_rdata;
  logic [255:0] rec_data;
  logic [11:0] ch_locked, ch_bit_valid, ch_nav_valid;
  logic        error_valid, rec_last;
  logic [31:0] error_code;

  b1i_rx_top #(.N_LANES(4), .BUF_DEPTH(256), .USE_SRAM(1'b0)) dut (
    .clk(clk), .rst_n(rst_n),
    .byte_valid(byte_valid), .data_byte(data_byte), .byte_ready(byte_ready),
    .sram_run(1'b0), .sram_pace_en(1'b0), .sram_pace_inc(32'd0),
    .sram_sample_total(32'd0), .sram_rd(), .sram_addr(), .sram_rdata(8'd0),
    .sram_rvalid(1'b0), .sram_done(),
    .cfg_valid(cfg_valid), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata),
    .cfg_ready(), .cfg_rdata(cfg_rdata),
    .rec_valid(rec_valid), .rec_ready(rec_ready), .rec_data(rec_data), .rec_last(rec_last),
    .ch_locked(ch_locked), .ch_bit_valid(ch_bit_valid), .ch_nav_valid(ch_nav_valid),
    .error_valid(error_valid), .error_code(error_code));

  task automatic cfgw(input [7:0] a, input [31:0] d);
    begin
      @(negedge clk);
      cfg_valid = 1; cfg_addr = a; cfg_wdata = d;
      @(negedge clk);
      cfg_valid = 0;
    end
  endtask

  integer errors = 0, nrec = 0, n_epoch = 0, n_meas = 0, n_stat = 0, n_last = 0;
  integer bytes_sent, wait_c;

  always @(posedge clk) begin
    if (rst_n && rec_valid && rec_ready) begin
      nrec++;
      if (rec_last) n_last++;
      case (rec_data[255:252])
        REC_EPOCH: n_epoch++;
        REC_MEAS:  n_meas++;
        REC_STATUS: n_stat++;
        default: ;
      endcase
    end
  end

  initial begin
    rst_n = 0; byte_valid = 0; data_byte = 0; cfg_valid = 0;
    cfg_addr = 0; cfg_wdata = 0; rec_ready = 1;
    repeat (4) @(negedge clk);
    rst_n = 1;

    cfgw(8'h15, 32'd2);                 // 2 ms 一个历元
    cfgw(8'h00, 32'd1);                 // run
    cfgw(8'h21, 32'd0);
    cfgw(8'h22, 32'd0);
    cfgw(8'h23, 32'd0);
    cfgw(8'h20, 32'h0000_0301);         // force ch=0 prn=3

    wait_c = 0;
    while (!dut.ch_enable[0] && wait_c < 5000) begin
      @(negedge clk); wait_c++;
    end
    if (!dut.ch_enable[0]) begin
      $display("FAIL: channel 0 not enabled after force");
      errors++;
    end

    bytes_sent = 0;
    while (bytes_sent < 3 * (SAMPLES_PER_MS / 4)) begin
      @(negedge clk);
      if (byte_ready) begin
        byte_valid = 1;
        data_byte  = 8'h1B;
        bytes_sent++;
      end else begin
        byte_valid = 0;
      end
    end
    byte_valid = 0;
    repeat (200) @(negedge clk);

    $display("records=%0d epoch=%0d meas=%0d status=%0d last=%0d enable0=%b",
             nrec, n_epoch, n_meas, n_stat, n_last, dut.ch_enable[0]);
    $display("dbg epoch_ms=%0d sample_count=%0d tb_ms=%0d ep_pend=%b fifo_cnt=%0d wr_ready=%b",
             dut.epoch_ms, dut.sample_count, dut.tb_ms_count, dut.ep_pend,
             dut.fifo_cnt, dut.fifo_wr_ready);
    if (n_epoch < 1) begin $display("FAIL: no EPOCH"); errors++; end
    if (n_meas < 12) begin $display("FAIL: meas %0d < 12", n_meas); errors++; end
    if (n_last < 1) begin $display("FAIL: rec_last never asserted"); errors++; end

    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d", errors);
    $finish;
  end

  initial begin
    #20_000_000;
    $display("FAIL: timeout, rec=%0d", nrec);
    $finish;
  end

endmodule
