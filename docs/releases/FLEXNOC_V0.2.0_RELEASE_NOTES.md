# FlexNoC v0.2.0 Release Notes — Release Candidate 1 (RC1)

- **Release Version**: `v0.2.0-rc1`
- **Release Target**: Production Baseline Multi-Core Interconnect IP
- **Date**: 2026-11-21
- **Repository**: `partialHuman/FlexNoC`
- **Base Commit**: `c7edd55` (PR #1 Merged into `main`)
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
- Added 16-node concurrent injection: all 16 mesh nodes simultaneously inject traffic into the network on the exact same clock cycle. Verified that all 16 packets route to their destinations with zero packet loss, zero deadlocks, and verified latency bounds.
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
| **Total** | **Regression Suite** | | **Complete RTL Coverage** | **3,472** | **100% PASS** | **~1.5s** |

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
> **Synthesis Metrics Note**: Reported cell counts reflect unmapped generic logic gates and DFF primitives generated by Yosys for structural RTL audit. They do not represent physical ASIC standard-cell area or FPGA LUT/FF utilization, which vary depending on the target foundry PDK or FPGA architecture. Linear scaling is observed across mesh configurations ($2,064 \times 4 = 8,256$ cells).

---

## 5. Performance Benchmark Methodology & Empirical Results

Benchmark sweeps were conducted across 24 empirical load points using `scripts/run_experiments.py` on a $4\times 4$ mesh (16 nodes, 100 MHz clock):

- **Traffic Patterns**:
  1. *Uniform Random*: Destination chosen uniformly at random across all network nodes ($dst \ne src$).
  2. *Hotspot Contention*: 30% of traffic directed to Node 5; remaining 70% uniformly distributed.
  3. *Neighbor Traffic*: All nodes send exclusively to their immediate grid neighbor $(x+1 \pmod 4, y)$.
- **Offered Rates**: Swept at 5%, 10%, 15%, 20%, 25%, 30%, 40%, 50% Bernoulli trial injection rate per node per cycle.
- **Simulation Duration & Target**: 400 packets injected per workload sweep point.
- **Drain Methodology**: Injection ceases after 400 packets; simulation executes up to 2,000 drain cycles until all in-flight packets are delivered.
- **Throughput Definition**: Aggregate delivered flits across the entire 16-node mesh divided by total simulation elapsed cycles (`flits/cycle`).
- **Latency Definition**: Ejection cycle minus injection cycle embedded in flit payload; sampled across all delivered packets.
- **Packet Loss**: Computed as `((total_injected - total_delivered) / total_injected) * 100%`.

### Benchmark Results Table (4x4 Mesh)

| Workload | Injection Rate | Aggregate Throughput (flits/cyc) | Avg Latency (cyc) | p50 Latency | p95 Latency | Packet Loss |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Uniform Random** | 5% | 0.7447 | 4.81 | 5 | 7 | **0.00%** |
| **Uniform Random** | 10% | 1.4768 | 4.83 | 5 | 7 | **0.00%** |
| **Uniform Random** | 20% | 3.0702 | 4.91 | 5 | 7 | **0.00%** |
| **Uniform Random** | 30% | 4.6053 | 5.07 | 5 | 8 | **0.00%** |
| **Uniform Random** | 50% | 6.3636 | 5.66 | 5 | 10 | **0.00%** |
| **Hotspot (30% to N5)** | 5% | 0.7495 | 4.97 | 5 | 8 | **0.00%** |
| **Hotspot (30% to N5)** | 10% | 1.4894 | 5.02 | 5 | 8 | **0.00%** |
| **Hotspot (30% to N5)** | 20% | 2.6316 | 10.25 | 6 | 39 | **0.00%** |
| **Hotspot (30% to N5)** | 40% | 2.5000 | 26.75 | 9 | 100 | **0.00%** |
| **Neighbor (1-hop)** | 5% | 0.7447 | 3.01 | 3 | 3 | **0.00%** |
| **Neighbor (1-hop)** | 10% | 1.4957 | 3.03 | 3 | 3 | **0.00%** |
| **Neighbor (1-hop)** | 30% | 4.7945 | 3.17 | 3 | 4 | **0.00%** |
| **Neighbor (1-hop)** | 50% | 6.2500 | 3.60 | 3 | 6 | **0.00%** |

*All 24 test points achieved **0.00% packet loss** with complete delivery.*

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

# 2. RTL Lint Checks (Verilator)
python scripts/run_lint.py

# 3. Full Automated Regression (8 suites, 3,472 assertions)
python scripts/run_regression.py all

# 4. Yosys Logic Synthesis Verification (5 targets)
python scripts/run_synthesis.py

# 5. Multi-Workload Performance Benchmark Sweeps (24 points)
python scripts/run_experiments.py
```
