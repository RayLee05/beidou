// 北斗 B1I 基带处理器 —— RTL 源文件清单
// VCS   : vcs -full64 -sverilog -f rtl/filelist.f -f tb/<tb>.f -top <tb>
// 其它  : iverilog -g2012 -I rtl/include -I rtl/common <files>
+incdir+rtl/include
+incdir+rtl/common

rtl/common/carrier_lut.sv
rtl/common/sample_unpacker.sv
rtl/common/sample_timebase.sv
rtl/track/carrier_mixer_nco.sv
rtl/track/code_nco.sv
rtl/track/code_ram.sv
rtl/track/correlator_epl.sv
rtl/track/dll_loop.sv
rtl/track/fll_pll_loop.sv
rtl/track/tracking_channel.sv
