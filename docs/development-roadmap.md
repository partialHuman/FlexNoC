# FlexNoC Development Roadmap & Milestone Tracker

## 1. Project Overview & Mission

FlexNoC is a standalone, configurable, modular, packet-switched Network-on-Chip (NoC) IP implemented in synthesizable SystemVerilog. The primary objective is to deliver an industrial-grade, parameterizable 2D mesh interconnect suitable for multicore SoC architectures with deterministic XY routing, round-robin arbitration, ready/valid flow control, rigorous verification testbenches, cycle-accurate performance benchmarks, and synthesis reports.

---

## 2. Milestone Summary

| Phase | Description | Status | Target Criteria |
| :--- | :--- | :--- | :--- |
| **Phase 0** | Environment, Specification & Protocol Freeze | **In Progress** | Frozen packet layout, handshake contract, directory structure, tooling verified |
| **Phase 1** | Fundamental Building Blocks (FIFO, Route, Arbiter) | **Pending** | Unit tests passing 100%, standalone modules verified, zero lint errors |
| **Phase 2** | Single Router Integration & Verification | **Pending** | 5-port router integrated, contention & backpressure verified, Yosys lint clean |
| **Phase 3** | Router Verification Hardening | **Pending** | Randomized seedable tests, scoreboard verification, full fault diagnostic |
| **Phase 4** | 2×2 Mesh Network Integration | **Pending** | All-pairs reachability (12 directed flows), boundary handling, multi-hop latency |
| **Phase 5** | Performance Framework & Traffic Workloads | **Pending** | Cycle counters, throughput/latency curves, uniform/hotspot/neighbor benchmarks |
| **Phase 6** | Configurable 4×4 Mesh Scale-up | **Pending** | Parameterized mesh top, 16 nodes verified, stress tests & corner routing |
| **Phase 7** | Synthesis & Hardware Evaluation | **Pending** | Gate/cell count analysis across buffer depths, critical path timing |
| **Phase 8** | Release Packaging & CI Automation | **Pending** | Complete documentation, automated regression test suite, clean portfolio demo |

---

## 3. Detailed Phase Breakdown & Exit Criteria

### Phase 0: Environment & Protocol Freeze
- **Scope**:
  - Environment inspection and toolchain setup.
  - Frozen specifications: `docs/architecture.md`, `docs/packet-format.md`, `docs/development-roadmap.md`.
  - Repository scaffold and build scripts.
- **Exit Criteria**:
  - All interface contracts, reset semantics, and coordinate mappings explicitly documented.
  - Compiler / simulator toolchain verified on baseline files.

### Phase 1: FIFO, Routing, and Arbitration
- **Scope**:
  - `input_fifo.sv`: Parameterized depth and data width, synchronous FIFO with simultaneous push/pop support and precise full/empty flags.
  - `route_compute.sv`: Pure combinational dimension-order XY route computation with local ejection and boundary check.
  - `round_robin_arbiter.sv`: Parameterized $N$-input arbiter with rotating priority pointer updated exclusively on accepted handshakes (`valid && ready`).
  - Unit testbenches with self-checking assertions for all corner cases.
- **Exit Criteria**:
  - Unit tests pass with 100% pass rate.
  - No latches, no implicit nets, no multiple drivers.

### Phase 2: Single Router Integration
- **Scope**:
  - `flexnoc_router.sv`: Five logical ports (North, East, South, West, Local).
  - 5 input FIFOs, 5 route computation engines, 5 round-robin arbiters, $5 \times 5$ crossbar switch.
  - Directed verification covering single-packet traversal, cross-port routing, simultaneous competing requests, downstream backpressure stalls, and simultaneous push/drain.
- **Exit Criteria**:
  - Router passes all directed test cases without loss, duplication, or corruption.
  - Downstream backpressure properly stalls input buffers without dropped flits.

### Phase 3: Router Verification Hardening
- **Scope**:
  - Independent scoreboard tracking injected vs. ejected flits.
  - Randomized traffic generator with reproducible PRNG seeds.
  - Handshake protocol assertions (stability of data during backpressure).
- **Exit Criteria**:
  - Regression of 10,000+ randomized packets across diverse contention profiles with zero lost/corrupted packets.

### Phase 4: 2×2 Mesh Network
- **Scope**:
  - `mesh_top.sv`: Interconnecting 4 routers $(X \in \{0,1\}, Y \in \{0,1\})$.
  - Direct router-to-router link binding with proper coordinate assignment.
  - Boundary link termination (unconnected ports driven inactive, ready deasserted).
  - Verification of all 12 directed node pairs plus concurrent injection.
- **Exit Criteria**:
  - All-pairs routing verified.
  - End-to-end scoreboard verifies 100% packet delivery integrity under multi-hop routing and backpressure.

### Phase 5: Performance Measurement Framework
- **Scope**:
  - Cycle-accurate performance instrumentation (`performance_monitor`).
  - Metrics: Accepted offered load, delivered throughput, average latency, p95/p99 tail latency, buffer utilization, stall cycles.
  - Workload generators: Uniform random, hotspot contention, nearest neighbor, burst injection.
  - Python automated benchmarking and data export to CSV/JSON.
- **Exit Criteria**:
  - Automated benchmark script runs repeatable sweeps across offered loads.
  - Latency vs. throughput saturation curves generated.

### Phase 6: Configurable 4×4 Mesh Scale-Up
- **Scope**:
  - Generalize `mesh_top.sv` using SystemVerilog `generate` loops parameterized by `MESH_WIDTH` and `MESH_HEIGHT`.
  - Verification of 16-node network under uniform and transpose traffic.
- **Exit Criteria**:
  - Elaboration and regression passing for 4×4 mesh.
  - Corner-to-corner traffic (e.g. Node (0,0) to Node (3,3)) traversing 6 hops successfully.

### Phase 7: Synthesis & Architectural Trade-offs
- **Scope**:
  - Synthesis scripts using Yosys.
  - Area / logic cell count and critical path analysis.
  - Trade-off sweeps across FIFO depths (e.g. 2, 4, 8, 16 flits) and network dimensions.
- **Exit Criteria**:
  - Mapped gate statistics collected and documented in `docs/synthesis-methodology.md`.

### Phase 8: Final Packaging & Documentation
- **Scope**:
  - Professional README with architecture diagrams, quick-start guide, and benchmark charts.
  - Continuous Integration workflow configuration (`.github/workflows/ci.yml`).
  - Final project archive and reproducible demo scripts.
- **Exit Criteria**:
  - One-command test execution (`make test` or `python scripts/run_regression.py`).
  - Zero undocumented known defects.
