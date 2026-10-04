// tb_nh_bit_sync.sv -- 位同步：相位判定 + 比特判决（允许整体反相）
`include "b1i_params.svh"

module tb_nh_bit_sync;

  logic clk = 1'b0, rst_n;
  always #5 clk = ~clk;

  logic [31:0] in_mem [0:1999];
  integer      exp_start [0:199];
  integer      exp_bit [0:199];
  integer      p0, n_win, n_exp;

  logic        dump_valid, dump_partial, synced, bit_valid, bit_val;
  logic [31:0] dump_ms, bit_ms, bit_mag;
  logic [4:0]  bit_phase;
  logic signed [CORR_ACC_W-1:0] i_p;

  nh_bit_sync #(.BS_BITS(10)) dut (
    .clk(clk), .rst_n(rst_n), .clear(1'b0), .dump_valid(dump_valid), .dump_partial(dump_partial),
    .dump_ms(dump_ms), .i_p(i_p), .synced(synced), .bit_phase(bit_phase), .bit_valid(bit_valid),
    .bit_val(bit_val), .bit_ms(bit_ms), .bit_mag(bit_mag));

  integer errors = 0, nbits = 0, pol = -1, idx;

  always @(posedge clk) begin
    if (bit_valid) begin
      idx = (bit_ms - p0) / 20;
      if (bit_ms != exp_start[idx]) begin
        $display("ERROR bit_ms %0d not a bit start", bit_ms);
        errors++;
      end else begin
        if (pol < 0) pol = bit_val ^ exp_bit[idx];
        if ((bit_val ^ pol) != exp_bit[idx]) begin
          if (errors < 10) $display("ERROR bit @%0d: got %0d want %0d (pol %0d)", bit_ms,
                                    bit_val, exp_bit[idx], pol);
          errors++;
        end
      end
      nbits++;
    end
  end

  integer fd, rc, i;
  initial begin
    $readmemh("tb/vectors/bs_input.hex", in_mem);
    fd = $fopen("tb/vectors/bs_expected.txt", "r");
    rc = $fscanf(fd, "%d %d\n", p0, n_win);
    n_exp = 0;
    while (!$feof(fd)) begin
      rc = $fscanf(fd, "%d %d\n", exp_start[n_exp], exp_bit[n_exp]);
      if (rc == 2) n_exp++;
    end
    $fclose(fd);

    rst_n = 1'b0; dump_valid = 0; dump_partial = 0; dump_ms = 0; i_p = 0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    for (i = 0; i < n_win; i++) begin
      repeat (60) @(negedge clk);            // 两次 dump 之间留出串行计算时间
      dump_valid = 1; dump_partial = (i == 0); dump_ms = i; i_p = in_mem[i][CORR_ACC_W-1:0];
      @(negedge clk);
      dump_valid = 0;
    end
    repeat (100) @(negedge clk);
    $display("synced=%0d phase=%0d (expected %0d), %0d bits checked, polarity %0d",
             synced, bit_phase, p0, nbits, pol);
    if (!synced || bit_phase != p0) begin $display("ERROR: wrong bit phase"); errors++; end
    if (nbits < 40) begin $display("ERROR: too few bits"); errors++; end
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d", errors);
    $finish;
  end

endmodule
