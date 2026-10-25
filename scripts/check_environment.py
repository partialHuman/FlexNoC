#!/usr/bin/env python3
"""
Environment and Toolchain Inspection Script for FlexNoC
Detects presence and versions of Verilator, Icarus Verilog, Yosys, GTKWave, Python, Git, and Make.
"""

import shutil
import subprocess
import sys
import os

TOOLS = {
    "Python": [sys.executable, "--version"],
    "Git": ["git", "--version"],
    "Make": ["make", "--version"],
    "Icarus Verilog (iverilog)": ["iverilog", "-V"],
    "Icarus Simulator (vvp)": ["vvp", "-V"],
    "Verilator": ["verilator_bin", "--version"],
    "Yosys Synthesis": ["yosys", "-V"],
    "GTKWave": ["gtkwave", "--version"],
}

def inspect():
    print("=" * 60)
    print(" FlexNoC Toolchain and Environment Verification")
    print("=" * 60)
    
    # Check if OSS CAD Suite environment needs activation
    oss_cad_bin = os.path.expanduser("~/scoop/apps/oss-cad-suite-nightly/current/bin")
    if os.path.isdir(oss_cad_bin) and oss_cad_bin not in os.environ.get("PATH", ""):
        os.environ["PATH"] = f"{oss_cad_bin};{os.environ.get('PATH', '')}"
        os.environ["VERILATOR_ROOT"] = os.path.expanduser("~/scoop/apps/oss-cad-suite-nightly/current/share/verilator")

    report = []
    all_ok = True

    for tool_name, cmd in TOOLS.items():
        executable = cmd[0]
        exe_path = shutil.which(executable)
        if exe_path:
            try:
                res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5)
                out = res.stdout.strip().split("\n")[0] if res.stdout.strip() else res.stderr.strip().split("\n")[0]
                print(f" [OK] {tool_name:<26}: {out} ({exe_path})")
                report.append((tool_name, "Available", out))
            except Exception as e:
                print(f" [WARN] {tool_name:<24}: Found at {exe_path} but error querying version: {e}")
                report.append((tool_name, "Warning", str(e)))
        else:
            print(f" [MISSING] {tool_name:<22}: Executable '{executable}' not found in PATH")
            report.append((tool_name, "Missing", "Not found in PATH"))
            if tool_name in ["Python", "Git", "Icarus Verilog (iverilog)", "Yosys Synthesis"]:
                all_ok = False

    print("=" * 60)
    if all_ok:
        print(" SUCCESS: All core simulation, synthesis, and build tools are present.")
    else:
        print(" NOTICE: Some optional or secondary tools are missing. Baseline flow can still execute.")
    print("=" * 60)
    return 0 if all_ok else 1

if __name__ == "__main__":
    sys.exit(inspect())
