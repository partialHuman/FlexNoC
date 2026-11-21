# FlexNoC v0.2.0 Release Notes

- **Release Version**: `v0.2.0` (Stable Release)
- **Release Target**: Production Baseline Multi-Core Interconnect IP
- **Date**: 2026-11-21
- **Repository**: `partialHuman/FlexNoC`
- **Baseline Release**: `v0.1.0` (`8c6493b`)
- **Release History**:
  - `v0.2.0-rc1` (2026-11-21): Initial release candidate establishing architecture verification hardening and benchmark audit.
  - `v0.2.0` (2026-11-21): Stable release incorporating benchmark runner reliability hardening, independent dataset validation, and release evidence reconciliation.
- **License**: MIT License

---

## 1. Executive Summary

FlexNoC `v0.2.0` is an architecture hardening, verification expansion, and simulation portability release. Following the initial `v0.1.0` baseline, this release integrates a critical Icarus Verilog CI compatibility fix, expands self-checking verification coverage from 1,775 to **3,472 assertions (+95.6%)**, proves mutual exclusion across the $5\times 5$ crossbar switch, validates mid-flight asynchronous reset and backpressure stress resilience, and introduces an independent fault-injecting scoreboard.

All eight regression test suites pass with 100% success across Verilator lint, Icarus Verilog simulation, Yosys gate-level elaboration, and 24 empirical performance benchmark points.

---

## 2. Key Changes & Features Since v0.1.0

### 2.1 Icarus Verilog CI Portability Hotfix (PR #1)
- **Problem**: In standard Ubuntu package distributions of Icarus Verilog (v11/v12 on GitHub Actions runners), the procedural `break;` statement in `tb/mesh/tb_mesh_4x4.sv` at line 158 resulted in a fatal compilation error (`sorry: break statements not supported.`).
- **Resolution**: Replaced procedural `break;` with a portable compound loop condition (`for (... && !found)`) and hoisted loop indices to task scope. Merged into `main` via PR #1 (`c7edd55`).

### 2.2 Exhaustive 2D Mesh All-Pairs & Concurrency Expansion
- Expanded `tb/mesh/tb_mesh_4x4.sv` to execute an exhaustive sweep of all $16 \times 16 = 256$ ordered source-to-destination pairs.
- Added 16-node concurrent injection: all 16 mesh nodes simultaneously inject traffic into the network on the exact same clock cycle. Verified that all 16 packets route to their destinations with zero packet loss, zero deadlocks observed under evaluated scenarios, and verified latency bounds.
- Expanded 4x4 mesh verification checks from 665 to **2,297 self-checking assertions**.

### 2.3 Router Protocol, Reset & Backpressure Stress Testing
- Added mid-flight asynchronous reset stress test to `tb/router/tb_flexnoc_router.sv`: asserting `rst_n = 0` during active flit transmission immediately clears all internal buffers and egress valid signals. Post-reset recovery routes Subsequent packets with 100% integrity.
- Added 20-flit continuous stream routing under pseudo-random ready backpressure toggling with zero dropped or duplicated flits.
- Added 5-way simultaneous contention testing: five ingress ports targeting `PORT_LOCAL` simultaneously are arbitrated with mathematical round-robin fairness over 5 consecutive cycles.
- Expanded single router checks from 36 to **97 assertions**.

### 2.4 Scoreboard Fault-Injection Validation
- Introduced a dedicated negative-testing testbench: `tb/unit/tb_scoreboard_fault_injection.sv`.
- Deliberately injects four hardware-level failure modes into the scoreboard to prove detector efficacy:
  1. *Payload Bit Flip*: Caught by payload comparator.
  2. *Destination Misrouting*: Caught by node ID mismatch.
  3. *Packet Loss / Dropped Flit*: Caught by scoreboard drain timeout.
  4. *Duplicate Packet Delivery*: Caught by retirement bitmap tracker.
- Automated within regression runner via `scripts/run_regression.py`.

### 2.5 Benchmark Runner Hardening & Unit Testing
- Hardened `scripts/run_experiments.py` against silent failures: enforces output file pre-removal to eliminate stale data inheritance, checks simulation subprocess exit codes immediately, verifies output freshness, validates JSON schema and type safety, rejects non-finite values and integer overflows, and asserts monotonic latency percentiles.
- Added 34 automated regression unit tests in `tests/test_run_experiments.py` verifying detection of non-zero simulation exit codes, missing outputs, malformed JSON, non-finite values, integer overflow, stale files, and incomplete sweeps.

---

## 3. Comprehensive Verification Results

### 3.1 Automated Regression Breakdown (8/8 Passed)

| # | Test Suite | Hierarchy Level | Target Focus | Assertions | Result | Duration |
| :-: | :--- | :---: | :--- | :---: | :---: | :---: |
| 1 | `tb_input_fifo` | Unit | Synchronous FWFT buffer, simultaneous push/pop | 28 | **PASSED** | 0.11s |
| 2 | `tb_route_compute` | Unit | Exhaustive 256-coordinate XY route calculations | 770 | **PASSED** | 0.04s |
| 3 | `tb_round_robin_arbiter` | Unit | 100-cycle persistent contention fairness & stalls | 116 | **PASSED** | 0.05s |
| 4 | `tb_crossbar_switch` | Unit | $5\times 5$ crossbar non-blocking permutations | 35 | **PASSED** | 0.04s |
| 5 | `tb_flexnoc_router` | Integration | 5-way contention, mid-flight reset, backpressure | 97 | **PASSED** | 0.06s |
| 6 | `tb_mesh_2x2` | Integration | 4-node grid, 12 directed flows, backpressure | 125 | **PASSED** | 0.16s |
| 7 | `tb_mesh_4x4` | Integration | 16-node grid, 256 all-pairs, 16 concurrent injections | 2,297 | **PASSED** | 0.96s |
| 8 | `tb_scoreboard_fault_injection` | Unit | Scoreboard error trapping under fault injection | 4 | **PASSED** | 0.08s |
| **Total** | **Regression Suite** | | **Regression Test Suite Scope (8/8 Suites)** | **3,472** | **100% PASS** | **~1.5s** |

> [!NOTE]
> **Verification Scope & Assertion Distinction**:
> The 3,472 reported self-checking assertions validate protocol contracts, invariant assertions, routing correctness, buffer state transitions, crossbar mutual exclusion, and scoreboard retirement matching. They represent structural assertions evaluated dynamically across simulation cycles rather than line, branch, toggle, or expression coverage gathered by a coverage tool.

### 3.2 RTL Lint Status (Verilator)
- Tool: Verilator 5.053 devel (`verilator_bin --lint-only -Wall -Wno-DECLFILENAME`)
- Result: **Zero errors, zero warnings** across all 7 synthesizable RTL modules.

---

## 4. Logic Synthesis Results (Yosys)

RTL gate complexity was evaluated using Yosys generic logic gate elaboration (`scripts/run_synthesis.py`).

| Target Module | Top Entity | Total Cells | DFFs | MUXes | Combinational Logic |
| :--- | :--- | :---: | :---: | :---: | :---: |
| `input_fifo` | `input_fifo` | 36 | 13 | 2 | 21 |
| `round_robin_arbiter` | `round_robin_arbiter` | 24 | 3 | 2 | 19 |
| `flexnoc_router` | `flexnoc_router` | 515 | 81 | 10 | 424 |
| `mesh_2x2` | `mesh_top` (4 routers) | 2,064 | 276 | 40 | 1,748 |
| `mesh_4x4` | `mesh_top` (16 routers) | 8,256 | 1,056 | 160 | 7,040 |

> [!NOTE]
> **Synthesis Metrics Note**: Reported cell counts reflect unmapped generic logic gates and DFF primitives generated by Yosys for structural RTL audit. They do not represent physical ASIC standard-cell area or FPGA LUT/FF utilization, which vary depending on the target foundry PDK or FPGA architecture. Linear scaling is observed across mesh configurations ($2,064 \times 4 = 8,256$ cells). Furthermore, generic gate counts do not reflect physical post-layout PPA (power, performance, area), which require target technology PDK synthesis and physical place-and-route.

---

## 5. Performance Benchmark Methodology & Empirical Results

Benchmark sweeps were conducted across all 24 empirical load points using `scripts/run_experiments.py` on a $4\times 4$ mesh (16 nodes, 100 MHz clock):

- **Traffic Patterns**:
  1. *Uniform Random*: Destination chosen uniformly at random across all network nodes ($dst \ne src$).
  2. *Hotspot Contention*: Destination-selection rule selects Node 0 $(0, 0)$ with 30% probability per generation trial; remaining 70% uniformly distributed excluding the source ($dst \ne src$). When Node 0 is the generating source, the 30% selection permits local loopback ($dst = src = 0$). The 30% figure describes the destination-selection rule rather than the measured proportion of remote-only hotspot traffic.
  3. *Neighbor Traffic*: All nodes send to one of their adjacent Cartesian mesh neighbors $(|x_{dst} - x_{src}| + |y_{dst} - y_{src}| == 1)$.
- **Offered Rates**: Swept at 5%, 10%, 15%, 20%, 25%, 30%, 40%, 50% Bernoulli trial injection probability per node per cycle, evaluated on cycles where `in_local_ready == 1`.
- **Target Injected Flits**: Exactly 350 flits injected per sweep point ($350 \times 24 = 8,400$ total flits across the benchmark suite).
- **Simulation Duration & Drain**: Dynamic. Following injection of 350 flits, injection is ceased (`in_local_valid = '0`), and an autonomous drain phase of up to 2,000 cycles executes. Simulation completes when `total_delivered == total_injected`.
- **Throughput Definition**: Aggregate delivered flits across the entire 16-node mesh divided by total simulation elapsed cycles ($\Theta = N_{\text{delivered}} / T_{\text{sim}}$, in `flits/cycle`).
- **Latency Measurement Boundaries**: Cycle-accurate difference $L_i = T_{\text{eject}} - T_{\text{inject}}$. In the simulation harness, the cycle timestamp is sampled and stamped into the 16-bit payload field at the negative clock edge during injection preparation (`in_local_valid = 1`) prior to the rising-edge source FIFO handshake, and extracted upon rising-edge ejection handshake (`out_local_valid && out_local_ready`) at the destination local interface.
- **Packet Loss Calculation**: Computed as $100\% \times (1.0 - (N_{\text{delivered}} / N_{\text{injected}}))$. Incomplete drain or timeout triggers an explicit test error and simulation failure (`$finish(1)`).
- **Deadlock Observation**: Zero deadlocks observed across all 24 workload points under the standard endpoint consumption assumption (`out_local_ready = 1`).

### Benchmark Results Table (4x4 Mesh — All 24 Empirical Sweep Points)

> [!NOTE]
> **Note on Earlier Summaries**:
> Earlier draft reports displayed an abbreviated 13-row sample table for presentation brevity. The complete empirical dataset produced by `scripts/run_experiments.py` comprises all 24 points (8 injection rates $\times$ 3 traffic patterns), all of which are tabulated below directly from `results/experiments_summary.csv`.

| Workload | Offered Rate (%) | Injected Flits | Delivered Flits | Total Sim Cycles | Aggregate Throughput (flits/cyc) | Min Lat (cyc) | Avg Lat (cyc) | p50 Lat (cyc) | p95 Lat (cyc) | p99 Lat (cyc) | Max Lat (cyc) | Packet Loss (%) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Uniform Random** | 5% | 350 | 350 | 470 | 0.7447 | 3 | 4.81 | 5 | 7 | 8 | 8 | **0.00%** |
| **Uniform Random** | 10% | 350 | 350 | 237 | 1.4768 | 3 | 4.83 | 5 | 7 | 8 | 8 | **0.00%** |
| **Uniform Random** | 15% | 350 | 350 | 155 | 2.2581 | 3 | 4.95 | 5 | 7 | 8 | 10 | **0.00%** |
| **Uniform Random** | 20% | 350 | 350 | 114 | 3.0702 | 3 | 4.91 | 5 | 7 | 9 | 10 | **0.00%** |
| **Uniform Random** | 25% | 350 | 350 | 101 | 3.4653 | 3 | 4.86 | 5 | 7 | 9 | 9 | **0.00%** |
| **Uniform Random** | 30% | 350 | 350 | 76 | 4.6053 | 3 | 5.07 | 5 | 8 | 9 | 11 | **0.00%** |
| **Uniform Random** | 40% | 350 | 350 | 64 | 5.4688 | 3 | 5.55 | 5 | 9 | 13 | 13 | **0.00%** |
| **Uniform Random** | 50% | 350 | 350 | 55 | 6.3636 | 3 | 5.66 | 5 | 10 | 12 | 14 | **0.00%** |
| **Hotspot (30% to N0)** | 5% | 350 | 350 | 467 | 0.7495 | 2 | 4.97 | 5 | 8 | 8 | 10 | **0.00%** |
| **Hotspot (30% to N0)** | 10% | 350 | 350 | 235 | 1.4894 | 2 | 5.02 | 5 | 8 | 9 | 10 | **0.00%** |
| **Hotspot (30% to N0)** | 15% | 350 | 350 | 159 | 2.2013 | 2 | 6.93 | 5 | 22 | 32 | 34 | **0.00%** |
| **Hotspot (30% to N0)** | 20% | 350 | 350 | 133 | 2.6316 | 2 | 10.25 | 6 | 39 | 51 | 58 | **0.00%** |
| **Hotspot (30% to N0)** | 25% | 350 | 350 | 133 | 2.6316 | 2 | 11.98 | 6 | 38 | 55 | 58 | **0.00%** |
| **Hotspot (30% to N0)** | 30% | 350 | 350 | 119 | 2.9412 | 2 | 13.62 | 6 | 53 | 59 | 60 | **0.00%** |
| **Hotspot (30% to N0)** | 40% | 350 | 350 | 140 | 2.5000 | 2 | 26.75 | 9 | 100 | 110 | 113 | **0.00%** |
| **Hotspot (30% to N0)** | 50% | 350 | 350 | 113 | 3.0973 | 2 | 21.55 | 8 | 76 | 89 | 90 | **0.00%** |
| **Neighbor (1-hop)** | 5% | 350 | 350 | 470 | 0.7447 | 3 | 3.01 | 3 | 3 | 4 | 4 | **0.00%** |
| **Neighbor (1-hop)** | 10% | 350 | 350 | 234 | 1.4957 | 3 | 3.03 | 3 | 3 | 4 | 4 | **0.00%** |
| **Neighbor (1-hop)** | 15% | 350 | 350 | 152 | 2.3026 | 3 | 3.07 | 3 | 4 | 5 | 5 | **0.00%** |
| **Neighbor (1-hop)** | 20% | 350 | 350 | 112 | 3.1250 | 3 | 3.09 | 3 | 4 | 4 | 5 | **0.00%** |
| **Neighbor (1-hop)** | 25% | 350 | 350 | 99 | 3.5354 | 3 | 3.13 | 3 | 4 | 5 | 6 | **0.00%** |
| **Neighbor (1-hop)** | 30% | 350 | 350 | 73 | 4.7945 | 3 | 3.17 | 3 | 4 | 5 | 6 | **0.00%** |
| **Neighbor (1-hop)** | 40% | 350 | 350 | 60 | 5.8333 | 3 | 3.25 | 3 | 4 | 6 | 7 | **0.00%** |
| **Neighbor (1-hop)** | 50% | 350 | 350 | 56 | 6.2500 | 3 | 3.60 | 3 | 6 | 9 | 10 | **0.00%** |

*All 24 test points achieved **0.00% packet loss** with zero deadlocks observed under standard endpoint liveness assumptions.*

---

## 6. Distinction Between Verified Behavior and Forward-Looking Specifications

- **Verified v0.2.0 Baseline**:
  - Single-flit, fixed-width 32-bit packets (`dest_x[1:0]`, `dest_y[1:0]`, `src_x[1:0]`, `src_y[1:0]`, `pkt_id[7:0]`, `payload[15:0]`).
  - Purely single-cycle crossbar traversal per flit with round-robin arbitration.
  - Ready/valid credit-less flow control with First-Word-Fall-Through ingress FIFOs.
- **Forward-Looking v0.3.0 Specifications** (`docs/architecture/`):
  - The documents in `docs/architecture/` represent approved forward-looking architecture specifications for milestone v0.3.0 (multi-flit wormhole routing, head/body/tail framing, atomic output reservation locking, and 5-bit counter sizing).
  - These features are **not** implemented in v0.2.0 RTL and do not affect v0.2.0 execution.

---

## 7. Known Limitations

1. **Fixed Packet Width**: v0.2.0 RTL processes single-flit packets exclusively. Multi-flit support is defined in the v0.3.0 specification.
2. **Single Physical Channel**: No virtual channel multiplexing; links carry one flit buffer at a time.
3. **Oblivious XY Routing**: Routing decisions are purely deterministic; no dynamic congestion avoidance.
4. **Synchronous Single Clock**: All routers operate on a single synchronous clock domain.

---

## 8. Reproducibility Instructions

All verification and build steps can be reproduced from the project root using standard Python and open-source EDA tools:

```bash
# 1. Environment and toolchain verification
python scripts/check_environment.py

# 2. Benchmark Runner Unit Tests (34 tests)
python -m unittest discover tests

# 3. RTL Lint Checks (Verilator)
python scripts/run_lint.py

# 4. Full Automated Regression (8 suites, 3,472 assertions)
python scripts/run_regression.py all

# 5. Yosys Logic Synthesis Verification (5 targets)
python scripts/run_synthesis.py

# 6. Multi-Workload Performance Benchmark Sweeps (24 points)
python scripts/run_experiments.py
```
