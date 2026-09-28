// tb_acquisition_engine.sv -- 捕获引擎状态机与判决（定向）
//   码 RAM 装全 1 图案；输入交替 +/-3；跑 4 个假设，检查忙碌/完成/峰值/门限判决。
`include "b1i_params.svh"

module tb_acquisition_engine;

  logic clk = 1'b0, rst_n;
  logic sample_valid, start, code_we;
  logic signed [SAMPLE_W-1:0] sample;
  logic [10:0] code_waddr;
  logic code_wdata;
  logic busy, done, found;
  logic [CODE_PHASE_W-1:0] found_code_phase;
  logic signed [CORR_ACC_W-1:0] peak_mag;
  logic [15:0] hyp_index;

  integer errors, i, k, done_cnt;
  reg [7:0] sample_cnt;

  acquisition_engine dut (
    .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid), .sample(sample),
    .start(start), .doppler_word(32'd0), .code_start(32'd0),
    .code_step(32'd1048576), .num_hyp(16'd4), .threshold(26'sd0),
    .code_we(code_we), .code_waddr(code_waddr), .code_wdata(code_wdata),
    .busy(busy), .done(done), .found(found),
    .found_code_phase(found_code_phase), .peak_mag(peak_mag), .hyp_index(hyp_index));

  always #5 clk = ~clk;

  always @(posedge clk) if (rst_n && done) done_cnt = done_cnt + 1;

  initial begin
    errors = 0; done_cnt = 0; sample_cnt = 0;
    rst_n = 1'b0; sample_valid = 1'b0; start = 1'b0; sample = 3'sd0;
    code_we = 1'b0; code_waddr = 11'd0; code_wdata = 1'b0;

    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    // 装 PRN 码：全 1（仅为状态机测试，真实码表按 ICD 装入）
    for (i = 0; i < 2046; i = i + 1) begin
      @(negedge clk);
      code_we = 1'b1; code_waddr = i[10:0]; code_wdata = 1'b1;
    end
    @(negedge clk); code_we = 1'b0;

    // 启动
    @(negedge clk); start = 1'b1;
    @(negedge clk); start = 1'b0;

    // 灌 4 个假设 x 16368 个样本
    sample_valid = 1'b1;
    for (k = 0; k < 4; k = k + 1) begin
      for (i = 0; i < SAMPLES_PER_MS; i = i + 1) begin
        sample = 3'sd3;            // 常数输入 + 本地载波冻结在 0 相位 => 累加值可精确预测
        sample_cnt = sample_cnt + 1;
        @(negedge clk);
      end
    end
    sample_valid = 1'b0;
    repeat (10) @(negedge clk);

    if (done_cnt != 1) begin
      $display("FAIL: done 脉冲次数 %0d，期望 1", done_cnt);
      errors = errors + 1;
    end
    if (busy !== 1'b0) begin
      $display("FAIL: 结束时 busy 应为 0");
      errors = errors + 1;
    end
    if (hyp_index != 16'd3) begin
      $display("FAIL: 末假设编号 %0d，期望 3", hyp_index);
      errors = errors + 1;
    end
    if (found !== 1'b1) begin
      $display("FAIL: 门限 0 时 found 应为 1（峰值 %0d）", peak_mag);
      errors = errors + 1;
    end
    // 16368 个样本 x (+3) x cos(0)=511 = 25092144，逐位可预测
    if (peak_mag !== 26'sd25092144) begin
      $display("FAIL: 峰值 %0d，期望 25092144", peak_mag);
      errors = errors + 1;
    end
    // 码表是全 1 图案，各码相位的相关值相同，峰值记在第一个假设上。
    // 真实 PRN 的相关峰唯一，那时这里应等于真值码相位。
    if (found_code_phase !== 32'd0) begin
      $display("FAIL: 峰值码相位 %0d，期望 0", found_code_phase);
      errors = errors + 1;
    end

    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d", errors);
    $finish;
  end

  initial begin
    #200000000;
    $display("FAIL: 仿真超时");
    $finish;
  end

endmodule
