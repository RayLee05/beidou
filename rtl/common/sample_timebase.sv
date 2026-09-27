// =============================================================================
// sample_timebase.sv -- 公共样本时基：样本编号、1 ms / 20 ms / 6 s / 1 s 边界
//   sample_valid 每有效一次推进一个样本编号；停顿时保持（REQ-IN-003）
//   ms_boundary : 与"新 1 ms 窗口的第一个样本"同拍（组合脉冲）
//   ms_tick     : 与"1 ms 窗口的最后一个样本"同拍（组合脉冲）
//   计数器回绕为定义行为（REQ-TB-003）
// =============================================================================
`include "b1i_params.svh"

module sample_timebase (
  input  logic                      clk,
  input  logic                      rst_n,
  input  logic                      sample_valid,
  output logic [SAMPLE_INDEX_W-1:0] sample_index,
  output logic [SAMPLE_INDEX_W-1:0] sample_count,
  output logic [13:0]               sample_cnt_in_ms,
  output logic                      ms_boundary,
  output logic                      ms_tick,
  output logic                      bit_boundary,
  output logic                      subframe_boundary,
  output logic                      epoch_boundary,
  output logic [15:0]               ms_in_bit,
  output logic [31:0]               ms_count
);

  logic [15:0] bit_in_subframe;   // 0..299
  logic [2:0]  subframe_in_frame; // 0..4
  logic [5:0]  bit_in_epoch;      // 0..49 (1 s = 50 bit)

  // 与当前样本同拍的边界脉冲
  assign ms_boundary       = sample_valid && (sample_cnt_in_ms == 14'd0);
  assign ms_tick           = sample_valid && (sample_cnt_in_ms == SAMPLES_PER_MS-1);
  assign bit_boundary      = ms_boundary && (ms_in_bit == 16'd0);
  assign subframe_boundary = bit_boundary && (bit_in_subframe == 16'd0);
  assign epoch_boundary    = bit_boundary && (bit_in_epoch == 6'd0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sample_index     <= '0;
      sample_count     <= '0;
      sample_cnt_in_ms <= 14'd0;
      ms_in_bit        <= 16'd0;
      bit_in_subframe  <= 16'd0;
      subframe_in_frame<= 3'd0;
      bit_in_epoch     <= 6'd0;
      ms_count         <= 32'd0;
    end else if (sample_valid) begin
      sample_index <= sample_index + 1'b1;
      sample_count <= sample_count + 1'b1;

      if (sample_cnt_in_ms == SAMPLES_PER_MS-1) begin
        sample_cnt_in_ms <= 14'd0;
        ms_count         <= ms_count + 32'd1;

        // 20 ms = 1 个 D1 数据位
        if (ms_in_bit == 16'd19) begin
          ms_in_bit <= 16'd0;
          // 6 s = 1 个子帧 = 300 bit
          if (bit_in_subframe == 16'd299) begin
            bit_in_subframe <= 16'd0;
            subframe_in_frame <= (subframe_in_frame == 3'd4) ? 3'd0
                                                             : subframe_in_frame + 3'd1;
          end else begin
            bit_in_subframe <= bit_in_subframe + 16'd1;
          end
          // 1 s = 50 bit（公共输出历元）
          bit_in_epoch <= (bit_in_epoch == 6'd49) ? 6'd0 : bit_in_epoch + 6'd1;
        end else begin
          ms_in_bit <= ms_in_bit + 16'd1;
        end
      end else begin
        sample_cnt_in_ms <= sample_cnt_in_ms + 14'd1;
      end
    end
  end

endmodule
