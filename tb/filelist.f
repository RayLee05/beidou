// 测试台清单（与 rtl/filelist.f 一起使用；每次只用一个 -top）
// 行尾标记 "// slow" 的用例在 run_rtl_unit.py --quick 时跳过
+incdir+rtl/include
+incdir+rtl/common

tb/unit/tb_carrier_lut.sv
tb/unit/tb_sample_unpacker.sv
tb/unit/tb_sample_timebase.sv
tb/unit/tb_prn_code_gen.sv
tb/unit/tb_nh_bit_sync.sv
tb/unit/tb_d1_frame_sync.sv
tb/unit/tb_record_fifo.sv
tb/unit/tb_measurement_engine.sv
tb/unit/tb_d1_clear.sv
tb/unit/tb_channel_manager.sv
tb/system/tb_tracking_channel.sv  // slow
tb/system/tb_acquisition.sv       // slow
tb/system/tb_b1i_rx_top.sv        // slow
tb/system/tb_record_backpressure.sv
