# Formal entry is deliberately gated while real IO and timing models are absent.
# No fake PAD wrappers or unverified final.* files may be emitted by this stage.
puts "FATAL: Formal synthesis is not ready. See ../逻辑综合/实施计划.md."
puts "Required: matched PAD .db + standard-cell/PAD timing Verilog, real pad wrapper, frozen IO budget."
puts "Core exploration is available through scripts/synth_core.tcl."
exit 2
