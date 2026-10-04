// =============================================================================
// epoch_aggregator.sv -- 公共历元头记录
//   epoch_pulse 当拍冻结时标，避免 STATUS/NAV 推迟写入时 sample_count 漂走。
//   需求: REQ-MEAS-001, REQ-SYS-004
// =============================================================================
`include "b1i_params.svh"
`include "b1i_records.svh"

module epoch_aggregator (
  input  logic         clk,
  input  logic         rst_n,
  input  logic         epoch_pulse,
  input  logic [31:0]  epoch_id,
  input  logic [31:0]  sample_count,
  input  logic [11:0]  n_valid,
  input  logic         input_done,
  input  logic [31:0]  sow0_ms,
  output logic [255:0] epoch_rec
);

  logic [31:0] q_id, q_sc, q_sow;
  logic [11:0] q_nv;
  logic        q_done, ep_d;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      q_id <= '0; q_sc <= '0; q_nv <= '0; q_done <= 1'b0; q_sow <= '0; ep_d <= 1'b0;
    end else begin
      ep_d <= epoch_pulse;
      if (epoch_pulse) begin
        q_id   <= epoch_id;
        q_sc   <= sample_count;
        q_done <= input_done;
        q_sow  <= sow0_ms;
      end
      // n_valid 在 measurement_engine 同拍更新，下一拍才稳定
      if (ep_d) q_nv <= n_valid;
    end
  end

  assign epoch_rec = pack_epoch(q_id, q_sc, q_nv, q_done, q_sow);

endmodule
