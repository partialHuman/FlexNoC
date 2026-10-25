# ==============================================================================
# FlexNoC - Configurable Network-on-Chip
# Top-level Makefile for Lint, Simulation, Synthesis, and Benchmarking
# ==============================================================================

SHELL := pwsh.exe
.SHELLFLAGS := -NoProfile -Command

PYTHON ?= python

.PHONY: all help lint test-unit test-router test-mesh test synth benchmark clean

all: lint test

help:
	@Write-Host "======================================================================" -ForegroundColor Cyan
	@Write-Host " FlexNoC Build & Verification Targets:" -ForegroundColor Cyan
	@Write-Host "======================================================================" -ForegroundColor Cyan
	@Write-Host "  make help         - Display this help message"
	@Write-Host "  make env          - Verify environment and toolchain installation"
	@Write-Host "  make lint         - Run Verilator lint checks (-Wall on all RTL)"
	@Write-Host "  make test-unit    - Run all unit testbenches (FIFO, Arbiter, Route, XBar)"
	@Write-Host "  make test-router  - Run 5-port single router integration tests"
	@Write-Host "  make test-mesh    - Run 2x2 and 4x4 mesh integration tests"
	@Write-Host "  make test         - Run full automated regression test suite"
	@Write-Host "  make synth        - Run Yosys synthesis sweeps across all targets"
	@Write-Host "  make benchmark    - Run workload performance sweeps and export CSV/JSON"
	@Write-Host "  make clean        - Remove transient simulation binaries and temporary files"
	@Write-Host "======================================================================" -ForegroundColor Cyan

env:
	$(PYTHON) scripts/check_environment.py

lint:
	$(PYTHON) scripts/run_lint.py

test-unit:
	$(PYTHON) scripts/run_regression.py unit

test-router:
	$(PYTHON) scripts/run_regression.py router

test-mesh:
	$(PYTHON) scripts/run_regression.py mesh

test:
	$(PYTHON) scripts/run_regression.py all

synth:
	$(PYTHON) scripts/run_synthesis.py

benchmark:
	$(PYTHON) scripts/run_experiments.py

clean:
	@if (Test-Path results/*.vvp) { Remove-Item -Force results/*.vvp }
	@if (Test-Path results/*.ys) { Remove-Item -Force results/*.ys }
	@if (Test-Path *.vvp) { Remove-Item -Force *.vvp }
	@Write-Host "[CLEAN] Build and simulation artifacts removed." -ForegroundColor Green
