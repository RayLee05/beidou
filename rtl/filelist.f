// 北斗 B1I 基带处理器 —— RTL 源文件清单（VCS / ModelSim / Icarus / Vivado 共用）
// VCS      : vcs -full64 -sverilog -f rtl/filelist.f <tb> -top <tb>
// ModelSim : vlog -sv -f rtl/filelist.f -f tb/filelist.f   （见 sim/modelsim/sim.do）
+incdir+rtl/include
+incdir+rtl/common

rtl/common/carrier_lut.sv
rtl/common/sample_unpacker.sv
rtl/common/teacher_stream_frontend.sv
rtl/common/sample_timebase.sv
rtl/common/prn_code_gen.sv
rtl/track/carrier_mixer_nco.sv
rtl/track/code_nco.sv
rtl/track/code_ram.sv
rtl/track/correlator_epl.sv
rtl/track/track_loop.sv
rtl/track/tracking_channel.sv
rtl/common/sram_reader.sv
rtl/acq/acquisition.sv
rtl/sync/nh_bit_sync.sv
rtl/sync/d1_frame_sync.sv
rtl/track/channel_slice.sv
rtl/ctrl/channel_manager.sv
rtl/meas/record_fifo.sv
rtl/meas/measurement_engine.sv
rtl/meas/epoch_aggregator.sv
rtl/meas/public_record_encoder.sv
rtl/b1i_rx_top.sv
rtl/student_receiver_core.sv
