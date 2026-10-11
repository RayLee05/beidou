`include "b1i_params.svh"
`include "b1i_records.svh"
module tb_public_record_encoder;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;
  logic [63:0] sample_count=64'd16367999, hardware_cycles=64'd17000000, missing_ticks=0;
  logic finish=0, input_error=0, input_ready, record_valid, record_ready=0, overflow;
  logic [255:0] record_data;
  logic epoch_valid=0;
  logic [31:0] epoch_id=1;
  logic [N_CHANNELS-1:0] active='1, locked='1, nh_valid='1, frame_valid='1, time_valid='1;
  logic [N_CHANNELS-1:0][5:0] prn;
  logic [N_CHANNELS-1:0][7:0] generation;
  logic [N_CHANNELS-1:0] dump_valid=0, dump_partial=0, code_wrap=0, sf_valid=0;
  logic [N_CHANNELS-1:0][31:0] code_ms, dop_word, carrier_phase;
  logic [N_CHANNELS-1:0][47:0] code_phase, code_after_sample;
  logic [N_CHANNELS-1:0][25:0] prompt_i, prompt_q;
  logic [N_CHANNELS-1:0][19:0] anchor_sow, sf_sow;
  logic [N_CHANNELS-1:0][2:0] sf_id;
  logic [N_CHANNELS-1:0][223:0] sf_info;
  logic [N_CHANNELS-1:0][299:0] sf_raw;
  logic [N_CHANNELS-1:0][9:0][1:0] sf_word_fixes;
  logic [N_CHANNELS-1:0][9:0][63:0] sf_word_samples;
  logic [N_CHANNELS-1:0][9:0][47:0] sf_word_phases;
  logic [N_CHANNELS-1:0][9:0][31:0] sf_word_ms;
  logic acq_start=0, acq_done=0, acq_found=1;
  logic [5:0] acq_prn=63;
  logic [11:0] acq_lag_halfchip=12'd123;
  logic [31:0] acq_dop_word=-32'sd393216;
  logic [27:0] acq_peak=28'd100001;
  logic ev_valid=0;
  logic [3:0] ev_code=EV_LOST, ev_ch=3;
  logic [5:0] ev_prn=39;
  logic [7:0] ev_generation=9;
  public_record_encoder dut (.*);
  integer seen[7]='{0,0,0,0,0,0,0}, word_next[12];
  logic [11:0] common_seen=0, track_seen=0;
  integer cycles=0, fd;
  logic stalled=0;
  logic [255:0] held;
  always @(posedge clk) if (rst_n) begin
    integer kind,ch,w;
    if (stalled && (record_valid !== 1'b1 || record_data !== held)) $fatal(1,"unstable stalled output");
    stalled=record_valid && !record_ready; held=record_data;
    if (record_valid && record_ready) begin
      kind=int'(record_data[7:0]); ch=int'(record_data[17:14]); w=int'(record_data[155:152]);
      if (seen[6]!=0) $fatal(1,"record after END");
      if (kind<1 || kind>6) $fatal(1,"unknown record");
      seen[kind]++;
      for (int b=0; b<32; b++) $fwrite(fd,"%c",record_data[8*b+:8]);
      case (kind)
        1: begin
          if (track_seen[ch] || record_data[13:8] != 6'(ch+1) || record_data[31:30]!=3
              || !record_data[23] || $signed(record_data[119:96])!=-100000-ch
              || $signed(record_data[143:120])!=2345+ch || record_data[95:32]!=16367999)
            $fatal(1,"tracking snapshot/schema");
          track_seen[ch]=1;
        end
        2: begin
          if (w!=word_next[ch] || record_data[13:8]!=6'(ch+1) || record_data[31:24]!=8'(ch+5)
              || record_data[95:32] != 64'(1000000+ch*10000+w*327360)
              || record_data[125:96] != 30'(1000+ch*100+w)
              || record_data[196:181] != 16'(600*w+ch)) $fatal(1,"navigation identity/time/raw");
          if ((w==1 && record_data[151:126]!=26'(3000+ch))
              || (w>1 && record_data[151:126]!=26'(4000+ch*100+w))) $fatal(1,"navigation information");
          word_next[ch]++;
        end
        3: if (record_data[13:8]!=39 || record_data[31:24]!=9) $fatal(1,"loss identity");
        4: begin
          if (common_seen[ch] || record_data[95:32]!=16368000 || record_data[127:96]!=1
              || record_data[13:8]!=6'(ch+1) || record_data[159:144]!=16'(1000+ch+(ch%2))
              || record_data[202:171]!=32'(98765+ch) || !record_data[22]) $fatal(1,"atomic epoch");
          common_seen[ch]=1;
        end
        5: if (!record_data[18] || record_data[13:8]!=63 || record_data[109:96]!=492
               || record_data[223:160]!=64'd10000200001) $fatal(1,"acquisition result");
        6: if (record_data[95:32]!=64'd16368000 || record_data[19:18]!=0
               || record_data[223:160]!=0) $fatal(1,"END/count/error");
      endcase
    end
  end
  initial begin
    fd=$fopen("reports/sim/public_encoder.bin","wb");
    if (fd==0) $fatal(1,"output file");
    for (int i=0; i<12; i++) begin
      word_next[i]=1; prn[i]=6'(i+1); generation[i]=8'(i+5);
      code_ms[i]=32'(1000+i); code_phase[i]={11'(i),37'd124};
      code_after_sample[i]={11'(i+1),37'(98765+i)<<5}; code_wrap[i]=1'(i%2);
      dop_word[i]=32'(-300000+i); carrier_phase[i]=32'h81234567+32'(i);
      prompt_i[i]=26'((-100000-i)*4); prompt_q[i]=26'((2345+i)*4);
      anchor_sow[i]=100000; sf_sow[i]=100000; sf_id[i]=1;
      sf_info[i]='0; sf_raw[i]='0;
      for (int w=0; w<10; w++) begin
        sf_word_samples[i][w]=64'(1000000+i*10000+(w+1)*327360);
        sf_word_phases[i][w]={11'(i),37'(w*3271)}; sf_word_ms[i][w]=32'(600*(w+1)+i);
        sf_word_fixes[i][w]=2'(w%3); sf_raw[i][299-30*w-:30]=30'(1000+i*100+w+1);
        if (w==0) sf_info[i][223-:26]=26'(3000+i);
        else sf_info[i][197-22*(w-1)-:22]=22'(4000+i*100+w+1);
      end
    end
    repeat(3) @(negedge clk); rst_n=1;
    acq_start=1; @(negedge clk); acq_start=0;
    repeat(4) @(negedge clk);
    epoch_valid=1; dump_valid='1; sf_valid='1; acq_done=1; ev_valid=1;
    @(negedge clk); epoch_valid=0; dump_valid=0; sf_valid=0; ev_valid=0;
    sample_count=16368000; finish=1;
    // Destroy the live identity and payload: queued observations must survive.
    active=0; prn='1; generation='1; sf_raw=0; sf_info=0; sf_word_samples=0;
    repeat(80) @(negedge clk);
    if (input_ready || overflow) $fatal(1,"backpressure/overflow");
    while (seen[6]==0 && cycles<1000) begin
      @(negedge clk); cycles++; record_ready=(cycles%5!=1 && cycles%5!=2);
    end
    repeat(5) @(negedge clk); $fclose(fd);
    if (seen[1]!=12 || seen[2]!=120 || seen[3]!=1 || seen[4]!=12 || seen[5]!=1 || seen[6]!=1
        || overflow || common_seen!='1 || track_seen!='1) $fatal(1,"lost or duplicate record");
    $display("TEST PASSED"); $finish;
  end
endmodule
