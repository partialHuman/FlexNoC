#!/usr/bin/env python3
"""
Performance Benchmark Sweep and Workload Experiments for FlexNoC
Executes automated sweeps across offered loads and traffic patterns,
measuring throughput, average latency, p95/p99 tail latency, and saturation.
Exports results to CSV and JSON formats.
"""

import csv
import json
import math
import os
import subprocess
import sys
import time

class BenchmarkError(Exception):
    """Base exception for all benchmark runner and validation failures."""
    pass

class BenchmarkExecutionError(BenchmarkError):
    """Raised when simulation compilation or execution fails."""
    pass

class BenchmarkOutputError(BenchmarkError):
    """Raised when simulation output is missing, stale, or malformed."""
    pass

class BenchmarkValidationError(BenchmarkError):
    """Raised when simulation metrics fail schema or consistency validation."""
    pass

def setup_env():
    oss_root = os.path.expanduser("~/scoop/apps/oss-cad-suite-nightly/current")
    oss_bin = os.path.join(oss_root, "bin")
    oss_lib = os.path.join(oss_root, "lib")
    if os.path.isdir(oss_bin):
        os.environ["PATH"] = f"{oss_bin};{oss_lib};{os.environ.get('PATH', '')}"

def compile_benchmark(vvp_file="results/sim_perf.vvp"):
    os.makedirs(os.path.dirname(vvp_file) or ".", exist_ok=True)
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
    cmd = ["iverilog", "-g2012", "-Irtl/common", "-o", vvp_file] + sources
    print(f"Compiling performance testbench to {vvp_file}...")
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
    except FileNotFoundError as e:
        raise BenchmarkExecutionError(f"Compiler executable '{cmd[0]}' not found: {e}")
    except OSError as e:
        raise BenchmarkExecutionError(f"Failed to execute compiler command '{cmd[0]}': {e}")

    if res.returncode != 0:
        err_msg = res.stderr.strip() if res.stderr else res.stdout.strip()
        print(f"[ERROR] Compilation failed (exit code {res.returncode}):")
        if err_msg:
            print(err_msg)
        raise BenchmarkExecutionError(f"Performance testbench compilation failed:\n{err_msg}")
    return vvp_file

def validate_benchmark_data(data, traffic=None, rate=None, packets=None):
    """
    Validate the structure, types, and mathematical consistency of a benchmark output dictionary.
    Rejects missing fields, incorrect types, invalid ranges, and inconsistent relations.
    """
    if not isinstance(data, dict):
        raise BenchmarkValidationError(f"Expected benchmark data dictionary, got {type(data).__name__}")

    int_fields = [
        "traffic_pattern", "offered_rate", "injected", "delivered",
        "total_cycles", "min_latency", "p50_latency", "p95_latency",
        "p99_latency", "max_latency"
    ]
    for field in int_fields:
        if field not in data:
            raise BenchmarkValidationError(f"Missing required integer field: '{field}'")
        val = data[field]
        if not isinstance(val, int) or isinstance(val, bool):
            raise BenchmarkValidationError(
                f"Field '{field}' must be an integer (got {type(val).__name__}: {val})"
            )

    num_fields = ["throughput", "avg_latency"]
    for field in num_fields:
        if field not in data:
            raise BenchmarkValidationError(f"Missing required numeric field: '{field}'")
        val = data[field]
        if not isinstance(val, (int, float)) or isinstance(val, bool):
            raise BenchmarkValidationError(
                f"Field '{field}' must be numeric (got {type(val).__name__}: {val})"
            )
        if not math.isfinite(val):
            raise BenchmarkValidationError(
                f"Field '{field}' must be a finite real number (got {val})"
            )

    # Contextual matches
    if traffic is not None and data["traffic_pattern"] != traffic:
        raise BenchmarkValidationError(
            f"Traffic pattern mismatch: expected {traffic}, got {data['traffic_pattern']}"
        )
    if rate is not None and data["offered_rate"] != rate:
        raise BenchmarkValidationError(
            f"Offered rate mismatch: expected {rate}, got {data['offered_rate']}"
        )
    if packets is not None and data["injected"] != packets:
        raise BenchmarkValidationError(
            f"Injected packet count mismatch: expected {packets}, got {data['injected']}"
        )

    # Value constraints
    if data["injected"] <= 0:
        raise BenchmarkValidationError(f"Injected flit count must be positive, got {data['injected']}")
    if data["delivered"] != data["injected"]:
        raise BenchmarkValidationError(
            f"Incomplete drain / packet loss detected: injected={data['injected']}, delivered={data['delivered']}"
        )
    if data["total_cycles"] <= 0:
        raise BenchmarkValidationError(f"Total cycles must be positive, got {data['total_cycles']}")
    if data["throughput"] <= 0.0:
        raise BenchmarkValidationError(f"Throughput must be positive, got {data['throughput']}")
    if data["min_latency"] < 0:
        raise BenchmarkValidationError(f"min_latency cannot be negative, got {data['min_latency']}")
    if data["avg_latency"] < data["min_latency"]:
        raise BenchmarkValidationError(
            f"avg_latency ({data['avg_latency']}) cannot be less than min_latency ({data['min_latency']})"
        )

    # Percentile monotonic ordering: min <= p50 <= p95 <= p99 <= max
    if not (data["min_latency"] <= data["p50_latency"] <= data["p95_latency"] <= data["p99_latency"] <= data["max_latency"]):
        raise BenchmarkValidationError(
            f"Latency percentiles are not monotonically non-decreasing: "
            f"min={data['min_latency']}, p50={data['p50_latency']}, "
            f"p95={data['p95_latency']}, p99={data['p99_latency']}, max={data['max_latency']}"
        )

    return True

def run_point(vvp_file, traffic, rate, packets=350, seed=100, json_path="results/benchmark_summary.json", runner_cmd=None):
    """
    Execute a single performance benchmark point with strict subprocess checking and output isolation.
    """
    abs_json_path = os.path.abspath(json_path)

    # 1. Remove or isolate the expected output before each benchmark run
    if os.path.exists(abs_json_path):
        try:
            os.remove(abs_json_path)
        except OSError as e:
            raise BenchmarkOutputError(f"Failed to remove prior output file '{json_path}': {e}")

    start_time = time.time()

    if runner_cmd is None:
        cmd = [
            "vvp", vvp_file,
            f"+TRAFFIC={traffic}",
            f"+RATE={rate}",
            f"+PACKETS={packets}",
            f"+SEED={seed}"
        ]
    else:
        cmd = runner_cmd

    # 2. Execute simulation subprocess
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
    except FileNotFoundError as e:
        raise BenchmarkExecutionError(f"Simulator executable '{cmd[0]}' not found: {e}")
    except OSError as e:
        raise BenchmarkExecutionError(f"Failed to execute simulation command '{cmd[0]}': {e}")

    # 3. Check simulation return code and fail immediately on non-zero
    if res.returncode != 0:
        diag_parts = []
        if res.stdout:
            diag_parts.append(f"STDOUT:\n{res.stdout.strip()}")
        if res.stderr:
            diag_parts.append(f"STDERR:\n{res.stderr.strip()}")
        diag = "\n" + "\n".join(diag_parts) if diag_parts else ""
        raise BenchmarkExecutionError(
            f"Simulation failed with exit code {res.returncode} for traffic={traffic}, rate={rate}{diag}"
        )

    # 4. Require expected output file to exist
    if not os.path.exists(abs_json_path):
        diag_parts = []
        if res.stdout:
            diag_parts.append(f"STDOUT:\n{res.stdout.strip()}")
        if res.stderr:
            diag_parts.append(f"STDERR:\n{res.stderr.strip()}")
        diag = "\n" + "\n".join(diag_parts) if diag_parts else ""
        raise BenchmarkOutputError(
            f"Simulation finished with exit code 0 but '{json_path}' was not generated for traffic={traffic}, rate={rate}{diag}"
        )

    # 5. Verify the output was generated by the current run (freshness check)
    mtime = os.path.getmtime(abs_json_path)
    if mtime < start_time - 2.0:
        raise BenchmarkOutputError(
            f"Output file '{json_path}' is stale (file mtime {mtime} < run start {start_time})"
        )

    # 6. Parse JSON with explicit error handling
    try:
        with open(abs_json_path, "r", encoding="utf-8") as f:
            raw_text = f.read().strip()
        if not raw_text:
            raise BenchmarkOutputError(f"Benchmark output '{json_path}' is empty")
        data = json.loads(raw_text)
    except json.JSONDecodeError as e:
        raise BenchmarkOutputError(f"Failed to parse JSON from '{json_path}': {e}")
    except OSError as e:
        raise BenchmarkOutputError(f"Failed to read benchmark output '{json_path}': {e}")

    # 7. Validate required fields, types, and value constraints
    validate_benchmark_data(data, traffic=traffic, rate=rate, packets=packets)

    return data

def run_all_experiments(vvp_file="results/sim_perf.vvp", packets=350,
                        json_out="results/experiments_summary.json",
                        csv_out="results/experiments_summary.csv",
                        json_path="results/benchmark_summary.json"):
    patterns = [
        {"id": 0, "name": "Uniform Random"},
        {"id": 1, "name": "Hotspot Contention"},
        {"id": 2, "name": "Neighbor Traffic"},
    ]

    rates = [5, 10, 15, 20, 25, 30, 40, 50]
    expected_total_points = len(patterns) * len(rates)
    all_results = []

    print("\n" + "=" * 80)
    print(" Running FlexNoC Multi-Workload Performance Sweeps")
    print("=" * 80)

    for pat in patterns:
        print(f"\n--- Workload: {pat['name']} ---")
        print(f" {'Rate (%)':<10} | {'Throughput (flits/cyc)':<24} | {'Avg Lat':<10} | {'p50 Lat':<10} | {'p95 Lat':<10} | {'p99 Lat':<10} | {'Loss (%)':<10}")
        print("-" * 88)

        for r in rates:
            data = run_point(vvp_file, pat["id"], r, packets=packets, seed=42 + r, json_path=json_path)
            data["pattern_name"] = pat["name"]
            all_results.append(data)
            loss_pct = 100.0 * (1.0 - (data["delivered"] / data["injected"]))
            print(f" {r:<10} | {data['throughput']:<24.4f} | {data['avg_latency']:<10.2f} | {data['p50_latency']:<10} | {data['p95_latency']:<10} | {data['p99_latency']:<10} | {loss_pct:<10.2f}")

    if len(all_results) != expected_total_points:
        raise BenchmarkValidationError(
            f"Expected {expected_total_points} benchmark points, but gathered {len(all_results)}"
        )

    # Export to JSON
    os.makedirs(os.path.dirname(json_out) or ".", exist_ok=True)
    with open(json_out, "w", encoding="utf-8") as f:
        json.dump(all_results, f, indent=2)
    print(f"\n[INFO] Saved detailed results to {json_out}")

    # Export to CSV
    os.makedirs(os.path.dirname(csv_out) or ".", exist_ok=True)
    fieldnames = [
        "pattern_name", "traffic_pattern", "offered_rate", "injected", "delivered",
        "total_cycles", "throughput", "min_latency", "avg_latency", "p50_latency",
        "p95_latency", "p99_latency", "max_latency"
    ]
    with open(csv_out, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in all_results:
            writer.writerow(row)
    print(f"[INFO] Saved CSV table to {csv_out}")

    print("=" * 80)
    print(" Benchmark sweeps completed successfully.")
    print("=" * 80)
    return all_results

def main():
    setup_env()
    try:
        vvp_file = compile_benchmark()
        run_all_experiments(vvp_file)
        return 0
    except BenchmarkError as e:
        print(f"\n[FATAL ERROR] Benchmark runner failed:\n{e}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
