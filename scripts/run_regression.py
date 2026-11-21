#!/usr/bin/env python3
"""
Full Automated Regression Test Suite for FlexNoC
Executes all unit, router, and mesh integration testbenches with self-checking assertions.
"""

import os
import shutil
import subprocess
import sys
import time

TEST_SUITES = [
    {
        "name": "Unit: input_fifo",
        "category": "unit",
        "sources": ["rtl/fifo/input_fifo.sv", "tb/unit/tb_input_fifo.sv"],
        "top": "tb_input_fifo",
    },
    {
        "name": "Unit: route_compute",
        "category": "unit",
        "sources": ["rtl/common/flexnoc_pkg.sv", "rtl/routing/route_compute.sv", "tb/unit/tb_route_compute.sv"],
        "top": "tb_route_compute",
    },
    {
        "name": "Unit: round_robin_arbiter",
        "category": "unit",
        "sources": ["rtl/arbitration/round_robin_arbiter.sv", "tb/unit/tb_round_robin_arbiter.sv"],
        "top": "tb_round_robin_arbiter",
    },
    {
        "name": "Unit: crossbar_switch",
        "category": "unit",
        "sources": ["rtl/switch/crossbar_switch.sv", "tb/unit/tb_crossbar_switch.sv"],
        "top": "tb_crossbar_switch",
    },
    {
        "name": "Router: flexnoc_router (5-port)",
        "category": "router",
        "sources": [
            "rtl/common/flexnoc_pkg.sv",
            "rtl/fifo/input_fifo.sv",
            "rtl/routing/route_compute.sv",
            "rtl/arbitration/round_robin_arbiter.sv",
            "rtl/switch/crossbar_switch.sv",
            "rtl/router/flexnoc_router.sv",
            "tb/router/tb_flexnoc_router.sv"
        ],
        "top": "tb_flexnoc_router",
    },
    {
        "name": "Mesh: 2x2 Network (All-Pairs)",
        "category": "mesh",
        "sources": [
            "rtl/common/flexnoc_pkg.sv",
            "rtl/fifo/input_fifo.sv",
            "rtl/routing/route_compute.sv",
            "rtl/arbitration/round_robin_arbiter.sv",
            "rtl/switch/crossbar_switch.sv",
            "rtl/router/flexnoc_router.sv",
            "rtl/network/mesh_top.sv",
            "tb/mesh/tb_mesh_2x2.sv"
        ],
        "top": "tb_mesh_2x2",
    },
    {
        "name": "Mesh: 4x4 Network (16 Nodes)",
        "category": "mesh",
        "sources": [
            "rtl/common/flexnoc_pkg.sv",
            "rtl/fifo/input_fifo.sv",
            "rtl/routing/route_compute.sv",
            "rtl/arbitration/round_robin_arbiter.sv",
            "rtl/switch/crossbar_switch.sv",
            "rtl/router/flexnoc_router.sv",
            "rtl/network/mesh_top.sv",
            "tb/mesh/tb_mesh_4x4.sv"
        ],
        "top": "tb_mesh_4x4",
    },
    {
        "name": "Unit: scoreboard_fault_injection",
        "category": "unit",
        "sources": [
            "rtl/common/flexnoc_pkg.sv",
            "rtl/fifo/input_fifo.sv",
            "rtl/routing/route_compute.sv",
            "rtl/arbitration/round_robin_arbiter.sv",
            "rtl/switch/crossbar_switch.sv",
            "rtl/router/flexnoc_router.sv",
            "rtl/network/mesh_top.sv",
            "tb/unit/tb_scoreboard_fault_injection.sv"
        ],
        "top": "tb_scoreboard_fault_injection",
    },
]

def setup_env():
    oss_root = os.path.expanduser("~/scoop/apps/oss-cad-suite-nightly/current")
    oss_bin = os.path.join(oss_root, "bin")
    oss_lib = os.path.join(oss_root, "lib")
    if os.path.isdir(oss_bin):
        os.environ["PATH"] = f"{oss_bin};{oss_lib};{os.environ.get('PATH', '')}"
        os.environ["VERILATOR_ROOT"] = os.path.join(oss_root, "share", "verilator")

def run_test(test):
    vvp_file = f"results/{test['top']}.vvp"
    iverilog_cmd = ["iverilog", "-g2012", "-Irtl/common", "-o", vvp_file] + test["sources"]
    
    # 1. Compile
    comp_res = subprocess.run(iverilog_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if comp_res.returncode != 0:
        return {"status": "COMPILATION_FAILED", "log": comp_res.stderr}

    # 2. Simulate
    sim_cmd = ["vvp", vvp_file]
    t0 = time.time()
    sim_res = subprocess.run(sim_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
    dur = time.time() - t0

    out = sim_res.stdout
    passed = (sim_res.returncode == 0) and ("[ALL TESTS PASSED]" in out)
    status = "PASSED" if passed else "FAILED"
    
    return {"status": status, "duration": dur, "log": out}

def main():
    setup_env()
    os.makedirs("results", exist_ok=True)
    
    filter_cat = sys.argv[1] if len(sys.argv) > 1 else None

    print("=" * 70)
    print(" FlexNoC Automated Regression Test Suite")
    print("=" * 70)

    results = []
    total_passed = 0
    total_executed = 0

    for test in TEST_SUITES:
        if filter_cat and filter_cat not in test["category"] and filter_cat != "all":
            continue

        total_executed += 1
        print(f" Running {test['name']:<36} ... ", end="", flush=True)
        res = run_test(test)
        results.append((test["name"], res))

        if res["status"] == "PASSED":
            total_passed += 1
            print(f"[PASS] ({res['duration']:.2f}s)")
        else:
            print(f"[FAIL]")
            print("-" * 50)
            print(res.get("log", "Unknown error")[:1000])
            print("-" * 50)

    print("\n" + "=" * 70)
    print(f" REGRESSION SUMMARY: {total_passed}/{total_executed} Test Suites Passed")
    print("=" * 70)

    for name, res in results:
        status_str = f"[{res['status']}]"
        dur_str = f"{res.get('duration', 0.0):.2f}s" if 'duration' in res else "N/A"
        print(f"  {name:<42} : {status_str:<10} ({dur_str})")

    print("=" * 70)
    return 0 if (total_passed == total_executed) else 1

if __name__ == "__main__":
    sys.exit(main())
