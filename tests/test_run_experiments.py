#!/usr/bin/env python3
"""
Unit and Regression Tests for the FlexNoC Benchmark Runner (scripts/run_experiments.py).
Tests subprocess error detection, stale output prevention, output validation,
metric constraints, and failure handling without requiring real EDA tools.
"""

import copy
import json
import os
import shutil
import sys
import tempfile
import time
import unittest
from unittest.mock import MagicMock, patch

# Ensure repo root is on sys.path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from scripts.run_experiments import (
    BenchmarkError,
    BenchmarkExecutionError,
    BenchmarkOutputError,
    BenchmarkValidationError,
    validate_benchmark_data,
    compile_benchmark,
    run_point,
    run_all_experiments,
    main,
)

VALID_SAMPLE_DATA = {
    "traffic_pattern": 0,
    "offered_rate": 10,
    "injected": 350,
    "delivered": 350,
    "total_cycles": 237,
    "throughput": 1.4768,
    "min_latency": 3,
    "avg_latency": 4.83,
    "p50_latency": 5,
    "p95_latency": 7,
    "p99_latency": 8,
    "max_latency": 8,
}


class TestValidateBenchmarkData(unittest.TestCase):
    """Test validation of benchmark metric schema, types, and constraints."""

    def test_valid_data_passes(self):
        data = copy.deepcopy(VALID_SAMPLE_DATA)
        self.assertTrue(validate_benchmark_data(data, traffic=0, rate=10, packets=350))

    def test_missing_required_fields(self):
        required_fields = [
            "traffic_pattern", "offered_rate", "injected", "delivered",
            "total_cycles", "throughput", "min_latency", "avg_latency",
            "p50_latency", "p95_latency", "p99_latency", "max_latency"
        ]
        for field in required_fields:
            data = copy.deepcopy(VALID_SAMPLE_DATA)
            del data[field]
            with self.assertRaises(BenchmarkValidationError, msg=f"Should fail when missing {field}"):
                validate_benchmark_data(data, traffic=0, rate=10, packets=350)

    def test_boolean_rejected_for_integer_fields(self):
        for field in ["traffic_pattern", "offered_rate", "injected", "delivered", "total_cycles"]:
            data = copy.deepcopy(VALID_SAMPLE_DATA)
            data[field] = True
            with self.assertRaises(BenchmarkValidationError, msg=f"Should fail when {field} is boolean"):
                validate_benchmark_data(data, traffic=0, rate=10, packets=350)

    def test_string_rejected_for_numeric_fields(self):
        for field in ["throughput", "avg_latency"]:
            data = copy.deepcopy(VALID_SAMPLE_DATA)
            data[field] = "invalid_numeric"
            with self.assertRaises(BenchmarkValidationError, msg=f"Should fail when {field} is string"):
                validate_benchmark_data(data, traffic=0, rate=10, packets=350)

    def test_traffic_pattern_mismatch(self):
        data = copy.deepcopy(VALID_SAMPLE_DATA)
        data["traffic_pattern"] = 1
        with self.assertRaises(BenchmarkValidationError):
            validate_benchmark_data(data, traffic=0, rate=10, packets=350)

    def test_offered_rate_mismatch(self):
        data = copy.deepcopy(VALID_SAMPLE_DATA)
        data["offered_rate"] = 20
        with self.assertRaises(BenchmarkValidationError):
            validate_benchmark_data(data, traffic=0, rate=10, packets=350)

    def test_injected_count_mismatch(self):
        data = copy.deepcopy(VALID_SAMPLE_DATA)
        data["injected"] = 400
        data["delivered"] = 400
        with self.assertRaises(BenchmarkValidationError):
            validate_benchmark_data(data, traffic=0, rate=10, packets=350)

    def test_packet_loss_or_incomplete_drain_rejected(self):
        data = copy.deepcopy(VALID_SAMPLE_DATA)
        data["delivered"] = 349  # 1 packet dropped or undrained
        with self.assertRaises(BenchmarkValidationError):
            validate_benchmark_data(data, traffic=0, rate=10, packets=350)

    def test_negative_or_zero_values_rejected(self):
        # zero injected
        d1 = copy.deepcopy(VALID_SAMPLE_DATA)
        d1["injected"] = 0
        d1["delivered"] = 0
        with self.assertRaises(BenchmarkValidationError):
            validate_benchmark_data(d1)

        # zero total cycles
        d2 = copy.deepcopy(VALID_SAMPLE_DATA)
        d2["total_cycles"] = 0
        with self.assertRaises(BenchmarkValidationError):
            validate_benchmark_data(d2)

        # zero throughput
        d3 = copy.deepcopy(VALID_SAMPLE_DATA)
        d3["throughput"] = 0.0
        with self.assertRaises(BenchmarkValidationError):
            validate_benchmark_data(d3)

        # negative min latency
        d4 = copy.deepcopy(VALID_SAMPLE_DATA)
        d4["min_latency"] = -1
        with self.assertRaises(BenchmarkValidationError):
            validate_benchmark_data(d4)

    def test_avg_latency_below_min_latency_rejected(self):
        data = copy.deepcopy(VALID_SAMPLE_DATA)
        data["min_latency"] = 5
        data["avg_latency"] = 4.2
        with self.assertRaises(BenchmarkValidationError):
            validate_benchmark_data(data)

    def test_non_monotonic_percentiles_rejected(self):
        # p50 < min
        d1 = copy.deepcopy(VALID_SAMPLE_DATA)
        d1["min_latency"] = 6
        d1["p50_latency"] = 5
        with self.assertRaises(BenchmarkValidationError):
            validate_benchmark_data(d1)

        # p95 < p50
        d2 = copy.deepcopy(VALID_SAMPLE_DATA)
        d2["p50_latency"] = 10
        d2["p95_latency"] = 8
        with self.assertRaises(BenchmarkValidationError):
            validate_benchmark_data(d2)

        # p99 < p95
        d3 = copy.deepcopy(VALID_SAMPLE_DATA)
        d3["p95_latency"] = 15
        d3["p99_latency"] = 12
        with self.assertRaises(BenchmarkValidationError):
            validate_benchmark_data(d3)

        # max < p99
        d4 = copy.deepcopy(VALID_SAMPLE_DATA)
        d4["p99_latency"] = 20
        d4["max_latency"] = 18
        with self.assertRaises(BenchmarkValidationError):
            validate_benchmark_data(d4)

    def test_non_finite_numeric_metrics_rejected(self):
        # Throughput non-finite values (NaN, +Inf, -Inf)
        for val in [float("nan"), float("inf"), float("-inf")]:
            data = copy.deepcopy(VALID_SAMPLE_DATA)
            data["throughput"] = val
            with self.assertRaises(BenchmarkValidationError, msg=f"Should reject throughput={val}"):
                validate_benchmark_data(data, traffic=0, rate=10, packets=350)

        # Average latency non-finite values (NaN, +Inf, -Inf)
        for val in [float("nan"), float("inf"), float("-inf")]:
            data = copy.deepcopy(VALID_SAMPLE_DATA)
            data["avg_latency"] = val
            with self.assertRaises(BenchmarkValidationError, msg=f"Should reject avg_latency={val}"):
                validate_benchmark_data(data, traffic=0, rate=10, packets=350)

    def test_extremely_large_positive_throughput_rejected(self):
        data = copy.deepcopy(VALID_SAMPLE_DATA)
        data["throughput"] = 10**1000
        with self.assertRaises(BenchmarkValidationError, msg="Extremely large positive integer throughput must raise BenchmarkValidationError"):
            validate_benchmark_data(data, traffic=0, rate=10, packets=350)

    def test_extremely_large_negative_throughput_rejected(self):
        data = copy.deepcopy(VALID_SAMPLE_DATA)
        data["throughput"] = -(10**1000)
        with self.assertRaises(BenchmarkValidationError, msg="Extremely large negative integer throughput must raise BenchmarkValidationError"):
            validate_benchmark_data(data, traffic=0, rate=10, packets=350)

    def test_extremely_large_positive_avg_latency_rejected(self):
        data = copy.deepcopy(VALID_SAMPLE_DATA)
        data["avg_latency"] = 10**1000
        with self.assertRaises(BenchmarkValidationError, msg="Extremely large positive integer avg_latency must raise BenchmarkValidationError"):
            validate_benchmark_data(data, traffic=0, rate=10, packets=350)

    def test_extremely_large_negative_avg_latency_rejected(self):
        data = copy.deepcopy(VALID_SAMPLE_DATA)
        data["avg_latency"] = -(10**1000)
        with self.assertRaises(BenchmarkValidationError, msg="Extremely large negative integer avg_latency must raise BenchmarkValidationError"):
            validate_benchmark_data(data, traffic=0, rate=10, packets=350)

    def test_large_integer_overflow_does_not_escape(self):
        # Verify that OverflowError is explicitly converted to BenchmarkValidationError and never escapes
        for field in ["throughput", "avg_latency"]:
            for large_int in [10**1000, -(10**1000)]:
                data = copy.deepcopy(VALID_SAMPLE_DATA)
                data[field] = large_int
                try:
                    validate_benchmark_data(data, traffic=0, rate=10, packets=350)
                    self.fail(f"Expected BenchmarkValidationError for {field}={large_int}")
                except OverflowError:
                    self.fail(f"OverflowError escaped validation for {field}={large_int}")
                except BenchmarkValidationError:
                    pass


class TestRunPoint(unittest.TestCase):
    """Test run_point subprocess isolation, error detection, and freshness."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.json_path = os.path.join(self.temp_dir, "benchmark_summary.json")

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def _write_json(self, data, path=None):
        target = path or self.json_path
        with open(target, "w", encoding="utf-8") as f:
            json.dump(data, f)

    @patch("subprocess.run")
    def test_successful_simulation(self, mock_subproc):
        def side_effect(*args, **kwargs):
            self._write_json(VALID_SAMPLE_DATA)
            res = MagicMock()
            res.returncode = 0
            res.stdout = "Simulation completed"
            res.stderr = ""
            return res

        mock_subproc.side_effect = side_effect
        result = run_point("sim.vvp", traffic=0, rate=10, packets=350, json_path=self.json_path)
        self.assertIsNotNone(result)
        self.assertEqual(result["throughput"], 1.4768)
        self.assertEqual(result["delivered"], 350)

    @patch("subprocess.run")
    def test_nonzero_exit_code_fails_even_if_json_exists(self, mock_subproc):
        def side_effect(*args, **kwargs):
            self._write_json(VALID_SAMPLE_DATA)
            res = MagicMock()
            res.returncode = 1
            res.stdout = "Simulation error: timeout or packet loss"
            res.stderr = "Fatal error in testbench"
            return res

        mock_subproc.side_effect = side_effect
        with self.assertRaises(BenchmarkExecutionError) as ctx:
            run_point("sim.vvp", traffic=0, rate=10, packets=350, json_path=self.json_path)
        self.assertIn("exit code 1", str(ctx.exception))

    @patch("subprocess.run")
    def test_missing_output_json_fails(self, mock_subproc):
        res = MagicMock()
        res.returncode = 0
        res.stdout = "Finished without writing JSON"
        res.stderr = ""
        mock_subproc.return_value = res

        with self.assertRaises(BenchmarkOutputError) as ctx:
            run_point("sim.vvp", traffic=0, rate=10, packets=350, json_path=self.json_path)
        self.assertIn("was not generated", str(ctx.exception))

    @patch("subprocess.run")
    def test_malformed_json_fails(self, mock_subproc):
        def side_effect(*args, **kwargs):
            with open(self.json_path, "w", encoding="utf-8") as f:
                f.write('{"traffic_pattern": 0, "offered_rate": 10, incomplete...')
            res = MagicMock()
            res.returncode = 0
            return res

        mock_subproc.side_effect = side_effect
        with self.assertRaises(BenchmarkOutputError) as ctx:
            run_point("sim.vvp", traffic=0, rate=10, packets=350, json_path=self.json_path)
        self.assertIn("Failed to parse JSON", str(ctx.exception))

    @patch("subprocess.run")
    def test_empty_json_fails(self, mock_subproc):
        def side_effect(*args, **kwargs):
            with open(self.json_path, "w", encoding="utf-8") as f:
                f.write('')
            res = MagicMock()
            res.returncode = 0
            return res

        mock_subproc.side_effect = side_effect
        with self.assertRaises(BenchmarkOutputError) as ctx:
            run_point("sim.vvp", traffic=0, rate=10, packets=350, json_path=self.json_path)
        self.assertIn("empty", str(ctx.exception))

    @patch("subprocess.run")
    def test_stale_output_from_earlier_run_is_removed(self, mock_subproc):
        # Place stale output before run
        stale_data = copy.deepcopy(VALID_SAMPLE_DATA)
        stale_data["throughput"] = 999.99
        self._write_json(stale_data)

        # Simulation does NOT write anything (crashes or exits without writing)
        res = MagicMock()
        res.returncode = 0
        mock_subproc.return_value = res

        with self.assertRaises(BenchmarkOutputError):
            run_point("sim.vvp", traffic=0, rate=10, packets=350, json_path=self.json_path)

        # Stale file must have been removed prior to execution
        self.assertFalse(os.path.exists(self.json_path))

    @patch("subprocess.run")
    def test_stale_mtime_detected(self, mock_subproc):
        # Create a file whose mtime is explicitly set to 10 seconds in the past
        def side_effect(*args, **kwargs):
            self._write_json(VALID_SAMPLE_DATA)
            past_time = time.time() - 100.0
            os.utime(self.json_path, (past_time, past_time))
            res = MagicMock()
            res.returncode = 0
            return res

        mock_subproc.side_effect = side_effect
        with self.assertRaises(BenchmarkOutputError) as ctx:
            run_point("sim.vvp", traffic=0, rate=10, packets=350, json_path=self.json_path)
        self.assertIn("is stale", str(ctx.exception))


class TestRunAllExperiments(unittest.TestCase):
    """Test suite-level orchestration, error propagation, and output generation."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.json_out = os.path.join(self.temp_dir, "experiments_summary.json")
        self.csv_out = os.path.join(self.temp_dir, "experiments_summary.csv")
        self.bench_json = os.path.join(self.temp_dir, "benchmark_summary.json")

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    @patch("scripts.run_experiments.run_point")
    def test_sweep_aborts_immediately_on_point_failure(self, mock_run_point):
        # Points 0 and 1 succeed, point 2 fails
        def side_effect(vvp_file, traffic, rate, packets, seed, json_path):
            if rate == 15 and traffic == 0:
                raise BenchmarkExecutionError("Simulation failed at offered_rate=15")
            data = copy.deepcopy(VALID_SAMPLE_DATA)
            data["traffic_pattern"] = traffic
            data["offered_rate"] = rate
            return data

        mock_run_point.side_effect = side_effect

        with self.assertRaises(BenchmarkExecutionError):
            run_all_experiments(
                vvp_file="dummy.vvp",
                packets=350,
                json_out=self.json_out,
                csv_out=self.csv_out,
                json_path=self.bench_json
            )

        # No summary files should be created if sweep was incomplete
        self.assertFalse(os.path.exists(self.json_out))
        self.assertFalse(os.path.exists(self.csv_out))

    @patch("scripts.run_experiments.run_point")
    def test_full_sweep_generates_consistent_outputs(self, mock_run_point):
        def side_effect(vvp_file, traffic, rate, packets, seed, json_path):
            data = copy.deepcopy(VALID_SAMPLE_DATA)
            data["traffic_pattern"] = traffic
            data["offered_rate"] = rate
            return data

        mock_run_point.side_effect = side_effect

        results = run_all_experiments(
            vvp_file="dummy.vvp",
            packets=350,
            json_out=self.json_out,
            csv_out=self.csv_out,
            json_path=self.bench_json
        )

        self.assertEqual(len(results), 24)
        self.assertTrue(os.path.exists(self.json_out))
        self.assertTrue(os.path.exists(self.csv_out))

        with open(self.json_out, "r", encoding="utf-8") as f:
            jdata = json.load(f)
        self.assertEqual(len(jdata), 24)

    @patch("scripts.run_experiments.compile_benchmark")
    @patch("scripts.run_experiments.run_all_experiments")
    def test_main_returns_nonzero_on_failure(self, mock_run_all, mock_compile):
        mock_compile.return_value = "sim.vvp"
        mock_run_all.side_effect = BenchmarkExecutionError("Sim execution failed")

        ret = main()
        self.assertEqual(ret, 1)


class TestProcessLaunchFailures(unittest.TestCase):
    """Test handling of missing executables and OS launch failures."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.json_path = os.path.join(self.temp_dir, "benchmark_summary.json")

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    @patch("subprocess.run")
    def test_missing_iverilog_raises_execution_error(self, mock_subproc):
        mock_subproc.side_effect = FileNotFoundError(2, "No such file or directory: 'iverilog'")
        with self.assertRaises(BenchmarkExecutionError) as ctx:
            compile_benchmark(vvp_file=os.path.join(self.temp_dir, "test.vvp"))
        self.assertIn("iverilog", str(ctx.exception))
        self.assertIn("not found", str(ctx.exception))

    @patch("subprocess.run")
    def test_missing_vvp_raises_execution_error(self, mock_subproc):
        mock_subproc.side_effect = FileNotFoundError(2, "No such file or directory: 'vvp'")
        with self.assertRaises(BenchmarkExecutionError) as ctx:
            run_point("sim.vvp", traffic=0, rate=10, packets=350, json_path=self.json_path)
        self.assertIn("vvp", str(ctx.exception))
        self.assertIn("not found", str(ctx.exception))

    @patch("subprocess.run")
    def test_generic_oserror_in_compile_raises_execution_error(self, mock_subproc):
        mock_subproc.side_effect = OSError(13, "Permission denied")
        with self.assertRaises(BenchmarkExecutionError) as ctx:
            compile_benchmark(vvp_file=os.path.join(self.temp_dir, "test.vvp"))
        self.assertIn("iverilog", str(ctx.exception))
        self.assertIn("Permission denied", str(ctx.exception))

    @patch("subprocess.run")
    def test_generic_oserror_in_run_point_raises_execution_error(self, mock_subproc):
        mock_subproc.side_effect = OSError(13, "Permission denied")
        with self.assertRaises(BenchmarkExecutionError) as ctx:
            run_point("sim.vvp", traffic=0, rate=10, packets=350, json_path=self.json_path)
        self.assertIn("vvp", str(ctx.exception))
        self.assertIn("Permission denied", str(ctx.exception))

    @patch("scripts.run_experiments.compile_benchmark")
    def test_main_returns_1_on_missing_iverilog(self, mock_compile):
        mock_compile.side_effect = BenchmarkExecutionError("Compiler executable 'iverilog' not found: [Errno 2]")
        ret = main()
        self.assertEqual(ret, 1)

    @patch("scripts.run_experiments.compile_benchmark")
    @patch("scripts.run_experiments.run_all_experiments")
    def test_main_returns_1_on_missing_vvp(self, mock_run_all, mock_compile):
        mock_compile.return_value = "sim.vvp"
        mock_run_all.side_effect = BenchmarkExecutionError("Simulator executable 'vvp' not found: [Errno 2]")
        ret = main()
        self.assertEqual(ret, 1)

    @patch("scripts.run_experiments.compile_benchmark")
    def test_main_returns_1_on_generic_oserror(self, mock_compile):
        mock_compile.side_effect = BenchmarkExecutionError("Failed to execute compiler command 'iverilog': Permission denied")
        ret = main()
        self.assertEqual(ret, 1)


if __name__ == "__main__":
    unittest.main()
