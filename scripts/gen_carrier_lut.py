"""生成 RTL 载波查表 '`rtl/common/carrier_lut_table.svh`'。

用法: python scripts/gen_carrier_lut.py
表值来源: sw/b1i_ref/carrier_lut.py（Python 与 RTL 共用的唯一算法）
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import ROOT, bootstrap, write_text  # noqa: E402

bootstrap()
from b1i_ref import carrier_lut as cl  # noqa: E402

OUT = os.path.join(ROOT, "rtl", "common", "carrier_lut_table.svh")


def emit(func: str, values) -> str:
    lines = [f"function automatic logic signed [{cl.LUT_DATA_W-1}:0] {func}("
             f"input logic [{cl.LUT_ADDR_W-1}:0] addr);",
             "  case (addr)"]
    for k, v in enumerate(values):
        lit = f"{cl.LUT_DATA_W}'sd{v}" if v >= 0 else f"-{cl.LUT_DATA_W}'sd{abs(v)}"
        lines.append(f"    {cl.LUT_ADDR_W}'d{k}: {func} = {lit};")
    lines.append(f"    default: {func} = {cl.LUT_DATA_W}'sd0;")
    lines.append("  endcase")
    lines.append("endfunction")
    return "\n".join(lines)


def main() -> int:
    header = [
        "// ============================================================================",
        "// carrier_lut_table.svh -- 载波 sin/cos 查表（自动生成，请勿手工修改）",
        "//",
        "// 生成命令 : python scripts/gen_carrier_lut.py",
        "// 表值来源 : sw/b1i_ref/carrier_lut.py",
        f"// 表深     : {cl.LUT_DEPTH} 项（{cl.LUT_ADDR_W} bit 地址）",
        f"// 数据位宽 : {cl.LUT_DATA_W} bit 有符号，幅度上限 {cl.LUT_AMPL}",
        "// 寻址     : 相位累加器高 10 位 phase[31:22]",
        "// ============================================================================",
        "",
        f"`ifndef B1I_CARRIER_LUT_TABLE_SVH",
        f"`define B1I_CARRIER_LUT_TABLE_SVH",
        "",
    ]
    body = [emit("carr_cos", cl.COS), "", emit("carr_sin", cl.SIN), ""]
    footer = ["`endif // B1I_CARRIER_LUT_TABLE_SVH", ""]
    write_text(OUT, "\n".join(header + body + footer))
    s = cl.stats()
    print(f"已生成 {OUT}")
    print(f"  深度 {s['depth']}  数据位宽 {s['data_w']}  幅度上限 {s['ampl']}")
    print(f"  cos 范围 [{s['cos_min']}, {s['cos_max']}]  sin 范围 [{s['sin_min']}, {s['sin_max']}]")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
