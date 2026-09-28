# =============================================================================
# 北斗 B1I 基带处理器 —— RTL 回归 Makefile
#
# 目标环境：虚拟机 IC (RHEL 6.7, GNU make 3.81) + Synopsys VCS
# 本地兜底：装有 Icarus Verilog 的机器用 make IVERILOG=1
#
# 用法：
#   make                       # 编译并运行全部 testbench
#   make TEST=tb_carrier_lut   # 只跑一个
#   make list                  # 列出全部用例
#   make clean
#
# 注意：必须在仓库根目录执行（testbench 用相对路径读 tb/vectors/）。
# =============================================================================

TEST    ?=
SIMDIR  := reports/sim
RTLF    := rtl/filelist.f
TBS     := $(notdir $(basename $(filter %.sv,$(shell sed -n 's/^\(tb\/.*\.sv\).*/\1/p' tb/filelist.f))))
IVL     ?= 0
# VCS 2014 的 -debug_access 属于 LCA 特性，需要 -lca；默认不开调试
VCSFLAGS ?=

ifeq ($(TEST),)
TARGETS := $(TBS)
else
TARGETS := $(TEST)
endif

.PHONY: all list clean

all: $(TARGETS:%=run.%)

list:
	@echo "可用用例："
	@for t in $(TBS); do echo "  $$t"; done

# VCS 流程
run.%:
	@mkdir -p $(SIMDIR)
	@echo "=== 编译 $* (VCS) ==="
	vcs -full64 -sverilog +v2k -timescale=1ns/1ps \
	    -Mdir=$(SIMDIR)/csrc_$* -o $(SIMDIR)/simv_$* \
	    -f $(RTLF) $(firstword $(wildcard tb/unit/$*.sv tb/system/$*.sv)) -top $* 2>&1 | tee $(SIMDIR)/$*.compile.log
	@echo "=== 运行 $* ==="
	@cd . && ./$(SIMDIR)/simv_$* 2>&1 | tee $(SIMDIR)/$*.run.log
	@grep -q "TEST PASSED" $(SIMDIR)/$*.run.log && echo "[PASS] $*" || (echo "[FAIL] $*"; exit 1)

# Icarus 兜底：make IVERILOG=1 TEST=tb_carrier_lut
ifeq ($(IVERILOG),1)
run.%:
	@mkdir -p $(SIMDIR)
	iverilog -g2012 -o $(SIMDIR)/$*.vvp -I rtl/include -I rtl/common \
	    $(filter-out +incdir%,$(shell sed -n 's/^\(rtl\/.*\.sv\).*/\1/p' $(RTLF))) tb/$*.sv
	vvp $(SIMDIR)/$*.vvp
endif

clean:
	rm -rf $(SIMDIR)
