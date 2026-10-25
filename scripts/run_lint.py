#!/usr/bin/env python3
"""
RTL Lint Runner for FlexNoC using Verilator
"""

import os
import shutil
import subprocess
import sys

def main():
    print("=" * 60)
    print(" Running Verilator Lint on FlexNoC RTL")
    print("=" * 60)

    # Set up environment if needed
    oss_root = os.path.expanduser("~/scoop/apps/oss-cad-suite-nightly/current")
    oss_bin = os.path.join(oss_root, "bin")
    oss_lib = os.path.join(oss_root, "lib")
    if os.path.isdir(oss_bin):
        os.environ["PATH"] = f"{oss_bin};{oss_lib};{os.environ.get('PATH', '')}"
        os.environ["VERILATOR_ROOT"] = os.path.join(oss_root, "share", "verilator")

    verilator_exe = shutil.which("verilator_bin") or shutil.which("verilator")
    if not verilator_exe:
        print("[ERROR] Verilator not found in PATH!")
        return 1

    rtl_files = [
        "rtl/common/flexnoc_pkg.sv",
        "rtl/fifo/input_fifo.sv",
        "rtl/routing/route_compute.sv",
        "rtl/arbitration/round_robin_arbiter.sv",
        "rtl/switch/crossbar_switch.sv",
        "rtl/router/flexnoc_router.sv",
        "rtl/network/mesh_top.sv",
    ]

    cmd = [
        verilator_exe,
        "--lint-only",
        "-Wall",
        "-Wno-DECLFILENAME",
    ] + rtl_files

    print(f"Executing: {' '.join(cmd)}\n")
    res = subprocess.run(cmd, text=True)
    if res.returncode == 0:
        print("\n[LINT SUCCESS] Zero warnings, zero errors across all RTL modules.")
    else:
        print(f"\n[LINT FAILED] Verilator reported issues (exit code {res.returncode}).")
    return res.returncode

if __name__ == "__main__":
    sys.exit(main())
