`include "b1i_params.svh"
`include "b1i_records.svh"

module tb_measurement_engine;
  logic clk = 0, rst_n = 0, epoch_pulse = 0;
  always #5 clk = ~clk;
  logic [31:0] epoch_id = 1, sample_count = 0;
  logic [11:0] dump_valid = 0, dump_partial = 0, locked = 0;
  logic [11:0] bit_synced = 0, anchor_valid = 0, week_valid = 0;
  logic [11:0][31:0] dump_ms = 0, code_phase = 0, dop_word = 0, anchor_ms = 0;
  logic [11:0][19:0] anchor_sow = 0;
  logic [11:0][12:0] week = 0;
  logic [11:0][3:0] lock_cnt = 0;
  logic [11:0][2:0] ch_state = 0;
  logic [11:0][5:0] prn = 0;
  logic [11:0][7:0] generation = 0;
  wire [11:0][255:0] meas_rec;
  wire [11:0] n_valid;
  measurement_engine dut (.*);
  integer errors = 0;

  task automatic check(input logic ok, input string message);
    if (ok !== 1'b1) begin $display("FAIL: %s", message); errors++; end
  endtask
  task automatic snapshot;
    epoch_pulse = 1;
    @(negedge clk);
    epoch_pulse = 0; epoch_id++;
  endtask

  initial begin
    repeat (3) @(negedge clk);
    check(meas_rec === '0 && n_valid === 0, "all reset outputs defined");
    rst_n = 1;
    snapshot();
    check(!$isunknown(meas_rec), "idle epoch contains no X");
    check(n_valid == 0, "idle measurements invalid");

    ch_state[0] = CH_TRACK; prn[0] = 39; generation[0] = 1;
    locked[0] = 1; bit_synced[0] = 1; anchor_valid[0] = 1;
    lock_cnt[0] = 8; week[0] = 950; week_valid[0] = 1;
    anchor_ms[0] = 100; anchor_sow[0] = 345600;
    dump_ms[0] = 109; code_phase[0] = 32'h0001_2345; dop_word[0] = -1234;
    sample_count = 1000; dump_valid[0] = 1; dump_partial[0] = 1;
    snapshot();
    check(n_valid == 0, "partial window cannot establish measurement");
    dump_partial[0] = 0;
    snapshot();
    dump_valid = 0;
    check(n_valid == 1 && meas_rec[0][73:70] == 4'b1111, "usable complete window");
    check(meas_rec[0][201:170] == 345600010, "same-cycle dump uses new tx time");
    check(meas_rec[0][105:74] == 109 && $signed(meas_rec[0][137:106]) == -1234,
          "same-cycle dump uses new ms and Doppler");
    check(meas_rec[0][169:138] == 32'h0001_2345, "preserve NCO wrap residue");
    sample_count = 1010; code_phase[0] = 32'h0029_2345;
    snapshot();
    check(n_valid == 1 && meas_rec[0][169:138] == code_phase[0], "freeze actual NCO phase");
    locked[0] = 0;
    snapshot();
    check(n_valid == 0 && !meas_rec[0][73], "lock loss invalidates without new dump");
    locked[0] = 1; dump_valid[0] = 1;
    snapshot(); dump_valid = 0;
    generation[0] = 2; prn[0] = 63;
    snapshot();
    check(n_valid == 0 && meas_rec[0][247:242] == 63, "reallocated channel rejects old observation");

    dump_valid[0] = 1; bit_synced[0] = 0;
    snapshot(); dump_valid = 0;
    check(n_valid == 0, "bit synchronization required for transmit time");
    bit_synced[0] = 1;
    sample_count += 2 * SAMPLES_PER_MS;
    snapshot();
    check(n_valid == 0, "stale dump not reused forever");

    dump_valid[0] = 1; anchor_sow[0] = 604794;
    anchor_ms[0] = 100; dump_ms[0] = 6100;
    snapshot(); dump_valid = 0;
    check(n_valid == 1 && meas_rec[0][201:170] == 1, "transmit time wraps at week end");
    check(meas_rec[0][62:50] == 951 && meas_rec[0][49], "transmit week advances");
    if (errors == 0) $display("TEST PASSED");
    else $display("TEST FAILED: %0d", errors);
    $finish;
  end
  initial begin #100000; $display("TEST FAILED: timeout"); $finish; end
endmodule
