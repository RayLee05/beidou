// =============================================================================
// carrier_mixer_nco.sv -- 载波 NCO + I/Q 混频
//   phase_next = phase + freq_word（模 2^NCO_PHASE_W）
//   同一拍内用 phase_next 查表并混频（组合），寄存 phase_next
//   约定: I = x*cos, Q = -x*sin  => 输入 A*cos(th+phi) 时 Q/I ≈ tan(phi)
//   位宽: PROD_W = SAMPLE_W + CARR_LUT_DATA_W = 13 bit（全精度，不截位）
// =============================================================================
`include "b1i_params.svh"
`include "carrier_lut_table.svh"

module carrier_mixer_nco (
  input  logic                                        clk,
  input  logic                                        rst_n,
  input  logic                                        sample_valid,
  input  logic signed [SAMPLE_W-1:0]                  sample,
  input  logic [FREQ_WORD_W-1:0]                      freq_word,
  input  logic                                        load,
  input  logic [NCO_PHASE_W-1:0]                      phase_init,
  output logic [NCO_PHASE_W-1:0]                      phase,
  output logic signed [SAMPLE_W+CARR_LUT_DATA_W-1:0]  mix_i,
  output logic signed [SAMPLE_W+CARR_LUT_DATA_W-1:0]  mix_q
);

  localparam int PROD_W = SAMPLE_W + CARR_LUT_DATA_W;

  logic [NCO_PHASE_W-1:0]            phase_next;
  logic signed [CARR_LUT_DATA_W-1:0] cos_v, sin_v;
  logic signed [PROD_W-1:0]          prod_i, prod_q;

  assign phase_next = load ? phase_init : (phase + freq_word[FREQ_WORD_W-1:0]);

  carrier_lut u_lut (
    .phase (phase_next),
    .cos_v (cos_v),
    .sin_v (sin_v)
  );

  assign prod_i = sample * cos_v;
  assign prod_q = sample * sin_v;
  assign mix_i  = prod_i;
  assign mix_q  = -prod_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                   phase <= '0;
    else if (sample_valid)        phase <= phase_next;
  end

endmodule
