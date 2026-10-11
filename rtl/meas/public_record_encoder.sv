// Fixed 32-byte little-endian teacher records. Snapshots retain their original
// channel identity and measured time while the output is stalled. The sample
// source pauses while records drain; compute pipelines may finish normally.
`include "b1i_params.svh"
`include "b1i_records.svh"
module public_record_encoder (
  input logic clk, rst_n,
  input logic [63:0] sample_count, hardware_cycles,
  input logic finish, input_error,
  input logic [63:0] missing_ticks,
  output logic input_ready,
  output logic record_valid,
  input logic record_ready,
  output logic [255:0] record_data,
  output logic overflow,
  input logic epoch_valid,
  input logic [31:0] epoch_id,
  input logic [N_CHANNELS-1:0] active, locked, nh_valid, frame_valid, time_valid,
  input logic [N_CHANNELS-1:0][5:0] prn,
  input logic [N_CHANNELS-1:0][7:0] generation,
  input logic [N_CHANNELS-1:0] dump_valid, dump_partial, code_wrap,
  input logic [N_CHANNELS-1:0][31:0] code_ms, dop_word,
  input logic [N_CHANNELS-1:0][47:0] code_phase, code_after_sample,
  input logic [N_CHANNELS-1:0][31:0] carrier_phase,
  input logic [N_CHANNELS-1:0][25:0] prompt_i, prompt_q,
  input logic [N_CHANNELS-1:0][19:0] anchor_sow,
  input logic [N_CHANNELS-1:0] sf_valid,
  input logic [N_CHANNELS-1:0][2:0] sf_id,
  input logic [N_CHANNELS-1:0][19:0] sf_sow,
  input logic [N_CHANNELS-1:0][223:0] sf_info,
  input logic [N_CHANNELS-1:0][299:0] sf_raw,
  input logic [N_CHANNELS-1:0][9:0][1:0] sf_word_fixes,
  input logic [N_CHANNELS-1:0][9:0][63:0] sf_word_samples,
  input logic [N_CHANNELS-1:0][9:0][47:0] sf_word_phases,
  input logic [N_CHANNELS-1:0][9:0][31:0] sf_word_ms,
  input logic acq_start, acq_done, acq_found,
  input logic [5:0] acq_prn,
  input logic [11:0] acq_lag_halfchip,
  input logic [31:0] acq_dop_word,
  input logic [27:0] acq_peak,
  input logic ev_valid,
  input logic [3:0] ev_code, ev_ch,
  input logic [5:0] ev_prn,
  input logic [7:0] ev_generation
);
  logic [N_CHANNELS-1:0] track_pending, nav_pending, common_pending, loss_pending;
  logic [N_CHANNELS-1:0][255:0] track_q, common_q, loss_q;
  logic [N_CHANNELS-1:0][9:0][255:0] nav_q;
  logic [N_CHANNELS-1:0][3:0] nav_index;
  logic acq_pending, done_q, ended;
  logic [255:0] acq_q;
  logic [31:0] acq_cycles;
  logic acq_counting;
  logic [6:0] quiet;
  integer selected_ch, selected_kind;
  wire acq_event = acq_done && !done_q && !finish;
  wire loss_event = ev_valid && (ev_code == EV_LOST || ev_code == EV_RELEASED);
  wire events_now = (|dump_valid) || (|sf_valid) || epoch_valid || acq_event || loss_event;
  wire pending_any = (|track_pending) || (|nav_pending) || (|common_pending)
                    || (|loss_pending) || acq_pending;
  wire slot_ready = !record_valid || record_ready;
  // epoch_valid depends on the sample accepted this cycle: excluding it here
  // avoids a combinational ready/valid loop. Its snapshots stop the next sample.
  assign input_ready = !finish && !ended && !pending_any && !record_valid
                       && !(|dump_valid) && !(|sf_valid) && !acq_event && !loss_event;

  function automatic logic [255:0] header(input logic [7:0] kind,
      input logic [5:0] p, input logic [3:0] ch, input logic [63:0] count);
    logic [255:0] r;
    r = '0; r[7:0] = kind; r[13:8] = p; r[17:14] = ch; r[95:32] = count;
    return r;
  endfunction

  always_comb begin
    selected_ch = 0; selected_kind = 0;
    if (acq_pending) selected_kind = 5;
    for (int i = N_CHANNELS-1; i >= 0; i--) begin
      if (loss_pending[i]) begin selected_ch = i; selected_kind = 3; end
    end
    for (int i = N_CHANNELS-1; i >= 0; i--) begin
      if (track_pending[i]) begin selected_ch = i; selected_kind = 1; end
    end
    for (int i = N_CHANNELS-1; i >= 0; i--) begin
      if (nav_pending[i]) begin selected_ch = i; selected_kind = 2; end
    end
    for (int i = N_CHANNELS-1; i >= 0; i--) begin
      if (common_pending[i]) begin selected_ch = i; selected_kind = 4; end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : p_encode
    logic [255:0] r;
    logic [47:0] phase;
    logic [31:0] ms;
    if (!rst_n) begin
      track_pending <= '0; nav_pending <= '0; common_pending <= '0; loss_pending <= '0;
      track_q <= '0; nav_q <= '0; common_q <= '0; loss_q <= '0; nav_index <= '0;
      acq_pending <= 1'b0; acq_q <= '0; done_q <= 1'b0; ended <= 1'b0;
      acq_cycles <= '0; acq_counting <= 1'b0; quiet <= '0;
      record_valid <= 1'b0; record_data <= '0; overflow <= 1'b0;
    end else if (!ended) begin
      done_q <= acq_done;
      if (acq_start) begin acq_cycles <= '0; acq_counting <= 1'b1; end
      else if (acq_counting && acq_cycles != 32'hffffffff) acq_cycles <= acq_cycles + 32'd1;
      if (acq_done || finish) acq_counting <= 1'b0;
      if (!finish || events_now) quiet <= '0;
      else if (quiet != 7'd64) quiet <= quiet + 7'd1;

      if (record_valid && record_ready) record_valid <= 1'b0;
      if (slot_ready && selected_kind != 0) begin
        record_valid <= 1'b1;
        case (selected_kind)
          1: begin record_data <= track_q[selected_ch]; track_pending[selected_ch] <= 1'b0; end
          2: begin
            record_data <= nav_q[selected_ch][nav_index[selected_ch]];
            if (nav_index[selected_ch] == 4'd9) begin
              nav_pending[selected_ch] <= 1'b0; nav_index[selected_ch] <= '0;
            end else nav_index[selected_ch] <= nav_index[selected_ch] + 4'd1;
          end
          3: begin record_data <= loss_q[selected_ch]; loss_pending[selected_ch] <= 1'b0; end
          4: begin record_data <= common_q[selected_ch]; common_pending[selected_ch] <= 1'b0; end
          5: begin record_data <= acq_q; acq_pending <= 1'b0; end
          default: ;
        endcase
      end

      for (int i = 0; i < N_CHANNELS; i++) begin
        if (dump_valid[i] && !dump_partial[i] && active[i]) begin
          if (track_pending[i] && !(slot_ready && selected_kind == 1 && selected_ch == i))
            overflow <= 1'b1;
          else begin
            r = header(8'd1, prn[i], 4'(i), sample_count);
            r[21:18] = {time_valid[i], frame_valid[i], nh_valid[i], locked[i]};
            r[23] = 1'b1; r[31:30] = 2'd3; r[29:24] = generation[i][5:0];
            // Common scaling preserves Prompt I/Q phase without saturation.
            r[119:96] = prompt_i[i][25:2]; r[143:120] = prompt_q[i][25:2];
            r[175:144] = dop_word[i]; r[207:176] = carrier_phase[i];
            r[231:208] = code_phase[i][36:13]; r[242:232] = code_phase[i][47:37];
            r[255:243] = code_ms[i][12:0];
            track_q[i] <= r; track_pending[i] <= 1'b1;
          end
        end
        if (epoch_valid && active[i] && prn[i] != 0) begin
          if (common_pending[i] && !(slot_ready && selected_kind == 4 && selected_ch == i))
            overflow <= 1'b1;
          else begin
            // Called on the accepted boundary sample, before the NCO registers
            // update: use next phase and increment the local epoch if it wraps.
            phase = code_after_sample[i]; ms = code_ms[i] + 32'(code_wrap[i]);
            r = header(8'd4, prn[i], 4'(i), sample_count + 64'd1);
            r[21:18] = {time_valid[i], frame_valid[i], nh_valid[i], locked[i]};
            r[22] = locked[i] && nh_valid[i] && frame_valid[i] && time_valid[i];
            r[23] = 1'b1; r[31:24] = 8'd1; r[127:96] = epoch_id;
            r[143:128] = {8'd0, generation[i]}; r[159:144] = ms[15:0];
            r[170:160] = phase[47:37]; r[202:171] = phase[36:5];
            r[234:203] = dop_word[i]; r[254:235] = anchor_sow[i];
            r[255] = frame_valid[i] && time_valid[i];
            common_q[i] <= r; common_pending[i] <= 1'b1;
          end
        end
        if (sf_valid[i] && active[i]) begin
          if (nav_pending[i] && !(slot_ready && selected_kind == 2 && selected_ch == i
                                  && nav_index[i] == 4'd9)) overflow <= 1'b1;
          else begin
            for (int w = 0; w < 10; w++) begin
              phase = sf_word_phases[i][w];
              r = header(8'd2, prn[i], 4'(i), sf_word_samples[i][w]);
              r[21:18] = {time_valid[i], frame_valid[i], nh_valid[i], locked[i]};
              r[22] = 1'b1; r[31:24] = generation[i];
              r[125:96] = sf_raw[i][299 - 30*w -: 30];
              if (w == 0) r[151:126] = sf_info[i][223 -: 26];
              else r[151:126] = {4'd0, sf_info[i][197 - 22*(w-1) -: 22]};
              r[155:152] = 4'(w+1); r[158:156] = sf_id[i]; r[178:159] = sf_sow[i];
              r[180:179] = sf_word_fixes[i][w]; r[196:181] = sf_word_ms[i][w][15:0];
              r[207:197] = phase[47:37]; r[239:208] = phase[36:5];
              nav_q[i][w] <= r;
            end
            nav_pending[i] <= 1'b1; nav_index[i] <= '0;
          end
        end
      end
      if (loss_event && ev_ch < N_CHANNELS) begin
        if (loss_pending[ev_ch] && !(slot_ready && selected_kind == 3 && selected_ch == ev_ch))
          overflow <= 1'b1;
        else begin
          r = header(8'd3, ev_prn, ev_ch, sample_count); r[31:24] = ev_generation;
          loss_q[ev_ch] <= r; loss_pending[ev_ch] <= 1'b1;
        end
      end
      if (acq_event) begin
        if (acq_pending && !(slot_ready && selected_kind == 5)) overflow <= 1'b1;
        else begin
          r = header(8'd5, acq_prn, 4'd15, sample_count);
          r[18] = acq_found; r[109:96] = {acq_lag_halfchip, 2'd0};
          r[159:128] = acq_dop_word;
          r[223:160] = 64'(acq_peak) * 64'(acq_peak); r[255:224] = acq_cycles;
          acq_q <= r; acq_pending <= 1'b1;
        end
      end
      if (finish && quiet == 7'd64 && !pending_any && !record_valid && !events_now) begin
        r = header(8'd6, 6'd0, 4'd0, sample_count);
        r[18] = input_error; r[19] = overflow;
        r[159:96] = hardware_cycles; r[223:160] = missing_ticks;
        record_data <= r; record_valid <= 1'b1; ended <= 1'b1;
      end
    end else if (record_valid && record_ready) record_valid <= 1'b0;
  end
endmodule
