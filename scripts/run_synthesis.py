#!/usr/bin/env python3
"""
Automated Synthesis Evaluation Script for FlexNoC using Yosys
Synthesizes FIFO, Arbiter, Single Router, 2x2 Mesh, and 4x4 Mesh.
Captures cell counts, registers, multiplexers, and logic gates.
"""

import json
import os
import re
import subprocess
import sys

SYNTH_TARGETS = [
    {
        "name": "input_fifo",
        "top": "input_fifo",
        "sources": ["rtl/fifo/input_fifo.sv"],
        "params": ""
    },
    {
        "name": "round_robin_arbiter",
        "top": "round_robin_arbiter",
        "sources": ["rtl/arbitration/round_robin_arbiter.sv"],
        "params": ""
    },
    {
        "name": "flexnoc_router",
        "top": "flexnoc_router",
        "sources": [
            "rtl/common/flexnoc_pkg.sv",
            "rtl/fifo/input_fifo.sv",
            "rtl/routing/route_compute.sv",
            "rtl/arbitration/round_robin_arbiter.sv",
            "rtl/switch/crossbar_switch.sv",
            "rtl/router/flexnoc_router.sv"
        ],
        "params": ""
    },
    {
        "name": "mesh_2x2",
        "top": "mesh_top",
        "sources": [
            "rtl/common/flexnoc_pkg.sv",
            "rtl/fifo/input_fifo.sv",
            "rtl/routing/route_compute.sv",
            "rtl/arbitration/round_robin_arbiter.sv",
            "rtl/switch/crossbar_switch.sv",
            "rtl/router/flexnoc_router.sv",
            "rtl/network/mesh_top.sv"
        ],
        "params": "-chparam MESH_WIDTH 2 -chparam MESH_HEIGHT 2"
    },
    {
        "name": "mesh_4x4",
        "top": "mesh_top",
        "sources": [
            "rtl/common/flexnoc_pkg.sv",
            "rtl/fifo/input_fifo.sv",
            "rtl/routing/route_compute.sv",
            "rtl/arbitration/round_robin_arbiter.sv",
            "rtl/switch/crossbar_switch.sv",
            "rtl/router/flexnoc_router.sv",
            "rtl/network/mesh_top.sv"
        ],
        "params": "-chparam MESH_WIDTH 4 -chparam MESH_HEIGHT 4"
    }
]

def setup_env():
    oss_root = os.path.expanduser("~/scoop/apps/oss-cad-suite-nightly/current")
    oss_bin = os.path.join(oss_root, "bin")
    oss_lib = os.path.join(oss_root, "lib")
    if os.path.isdir(oss_bin):
        os.environ["PATH"] = f"{oss_bin};{oss_lib};{os.environ.get('PATH', '')}"

def synth_target(target):
    ys_script = f"results/synth_{target['name']}.ys"
    with open(ys_script, "w") as f:
        for s in target["sources"]:
            f.write(f"read_verilog -sv {s}\n")
        f.write(f"hierarchy -check -top {target['top']} {target['params']}\n")
        f.write("proc\nopt\nfsm\nopt\nmemory\nopt\nstat\n")

    cmd = ["yosys", "-s", ys_script]
    res = subprocess.run(cmd, capture_output=True, text=True)
    
    if res.returncode != 0:
        return {"error": res.stderr}

    log = res.stdout
    metrics = {"name": target["name"], "top": target["top"]}
    
    # Extract cell statistics
    cells_m = re.findall(r"Number of cells:\s+(\d+)", log)
    if not cells_m:
        cells_m = re.findall(r"(\d+)\s+cells", log)
    if cells_m:
        metrics["total_cells"] = int(cells_m[-1])

    # Count DFFs
    dff_m = re.findall(r"\$dff[a-z]*\s+(\d+)", log) + re.findall(r"\$adffe\s+(\d+)", log)
    metrics["flip_flops"] = sum(int(x) for x in dff_m) if dff_m else 0

    # Count Muxes
    mux_m = re.findall(r"\$mux\s+(\d+)", log)
    metrics["muxes"] = int(mux_m[-1]) if mux_m else 0

    return metrics

def main():
    setup_env()
    os.makedirs("results", exist_ok=True)

    print("=" * 70)
    print(" Running Yosys Synthesis Sweeps across FlexNoC Hierarchy")
    print("=" * 70)

    summary = []
    print(f" {'Module / Target':<24} | {'Top Level':<18} | {'Total Cells':<14} | {'Flip-Flops':<12} | {'MUXes':<8}")
    print("-" * 84)

    for tgt in SYNTH_TARGETS:
        m = synth_target(tgt)
        if "error" in m:
            print(f" {tgt['name']:<24} | ERROR: {m['error'][:40]}")
        else:
            summary.append(m)
            print(f" {m['name']:<24} | {m['top']:<18} | {m.get('total_cells', 'N/A'):<14} | {m.get('flip_flops', 'N/A'):<12} | {m.get('muxes', 'N/A'):<8}")

    out_json = "results/synthesis_summary.json"
    with open(out_json, "w") as f:
        json.dump(summary, f, indent=2)
    print(f"\n[INFO] Saved synthesis metrics to {out_json}")
    print("=" * 70)
    return 0

if __name__ == "__main__":
    sys.exit(main())
