#!/usr/bin/env python3
"""
Performance Benchmark Sweep and Workload Experiments for FlexNoC
Executes automated sweeps across offered loads and traffic patterns,
measuring throughput, average latency, p95/p99 tail latency, and saturation.
Exports results to CSV and JSON formats.
"""

import csv
import json
import os
import subprocess
import sys

def setup_env():
    oss_root = os.path.expanduser("~/scoop/apps/oss-cad-suite-nightly/current")
    oss_bin = os.path.join(oss_root, "bin")
    oss_lib = os.path.join(oss_root, "lib")
    if os.path.isdir(oss_bin):
        os.environ["PATH"] = f"{oss_bin};{oss_lib};{os.environ.get('PATH', '')}"

def compile_benchmark():
    os.makedirs("results", exist_ok=True)
    sources = [
        "rtl/common/flexnoc_pkg.sv",
        "rtl/fifo/input_fifo.sv",
        "rtl/routing/route_compute.sv",
        "rtl/arbitration/round_robin_arbiter.sv",
        "rtl/switch/crossbar_switch.sv",
        "rtl/router/flexnoc_router.sv",
        "rtl/network/mesh_top.sv",
        "tb/traffic/tb_mesh_performance.sv"
    ]
    vvp_file = "results/sim_perf.vvp"
    cmd = ["iverilog", "-g2012", "-Irtl/common", "-o", vvp_file] + sources
    print(f"Compiling performance testbench to {vvp_file}...")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print("[ERROR] Compilation failed:")
        print(res.stderr)
        sys.exit(1)
    return vvp_file

def run_point(vvp_file, traffic, rate, packets=400, seed=100):
    cmd = [
        "vvp", vvp_file,
        f"+TRAFFIC={traffic}",
        f"+RATE={rate}",
        f"+PACKETS={packets}",
        f"+SEED={seed}"
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    json_path = "results/benchmark_summary.json"
    if os.path.exists(json_path):
        with open(json_path, "r") as f:
            data = json.load(f)
        return data
    else:
        print(f"[WARN] Failed to read metrics for traffic={traffic}, rate={rate}")
        return None

def main():
    setup_env()
    vvp_file = compile_benchmark()

    patterns = [
        {"id": 0, "name": "Uniform Random"},
        {"id": 1, "name": "Hotspot Contention"},
        {"id": 2, "name": "Neighbor Traffic"},
    ]

    rates = [5, 10, 15, 20, 25, 30, 40, 50]
    all_results = []

    print("\n" + "=" * 80)
    print(" Running FlexNoC Multi-Workload Performance Sweeps")
    print("=" * 80)

    for pat in patterns:
        print(f"\n--- Workload: {pat['name']} ---")
        print(f" {'Rate (%)':<10} | {'Throughput (flits/cyc)':<24} | {'Avg Lat':<10} | {'p50 Lat':<10} | {'p95 Lat':<10} | {'p99 Lat':<10} | {'Loss (%)':<10}")
        print("-" * 88)

        for r in rates:
            data = run_point(vvp_file, pat["id"], r, packets=350, seed=42 + r)
            if data:
                data["pattern_name"] = pat["name"]
                all_results.append(data)
                loss_pct = 100.0 * (1.0 - (data["delivered"] / data["injected"]))
                print(f" {r:<10} | {data['throughput']:<24.4f} | {data['avg_latency']:<10.2f} | {data['p50_latency']:<10} | {data['p95_latency']:<10} | {data['p99_latency']:<10} | {loss_pct:<10.2f}")

    # Export to JSON
    json_out = "results/experiments_summary.json"
    with open(json_out, "w") as f:
        json.dump(all_results, f, indent=2)
    print(f"\n[INFO] Saved detailed results to {json_out}")

    # Export to CSV
    csv_out = "results/experiments_summary.csv"
    if all_results:
        fieldnames = ["pattern_name", "traffic_pattern", "offered_rate", "injected", "delivered", 
                      "total_cycles", "throughput", "min_latency", "avg_latency", "p50_latency", 
                      "p95_latency", "p99_latency", "max_latency"]
        with open(csv_out, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for row in all_results:
                writer.writerow(row)
        print(f"[INFO] Saved CSV table to {csv_out}")

    print("=" * 80)
    print(" Benchmark sweeps completed successfully.")
    print("=" * 80)
    return 0

if __name__ == "__main__":
    sys.exit(main())
