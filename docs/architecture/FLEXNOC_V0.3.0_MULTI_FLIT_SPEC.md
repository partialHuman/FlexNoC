# FlexNoC v0.3.0 — Multi-Flit Packet Architecture & Implementation Specification

- **Document Version**: 2.4 (Channel Dependency & Canonical Transfer Semantics Pass)
- **Status**: **APPROVED MASTER ARCHITECTURE SPECIFICATION**
- **Target Release**: FlexNoC v0.3.0
- **Authors**: FlexNoC Architecture, Verification, and Synthesis Teams
- **Associated Documents**:
  - [docs/architecture/FLEXNOC_V0.3.0_PACKET_FORMAT.md](FLEXNOC_V0.3.0_PACKET_FORMAT.md)
  - [docs/architecture/FLEXNOC_V0.3.0_ROUTER_STATE_MACHINE.md](FLEXNOC_V0.3.0_ROUTER_STATE_MACHINE.md)
  - [docs/architecture/FLEXNOC_V0.3.0_VERIFICATION_PLAN.md](FLEXNOC_V0.3.0_VERIFICATION_PLAN.md)
  - [docs/architecture/FLEXNOC_V0.3.0_DESIGN_REVIEW.md](FLEXNOC_V0.3.0_DESIGN_REVIEW.md)
  - [docs/architecture/FLEXNOC_V0.3.0_FINAL_CONSISTENCY_AUDIT.md](FLEXNOC_V0.3.0_FINAL_CONSISTENCY_AUDIT.md)

---

## 1. Executive Summary

This document establishes the authoritative technical architecture for **multi-flit packet support** in FlexNoC v0.3.0.

In versions v0.1.0 and v0.2.0, FlexNoC implemented a proven single-flit 2D mesh interconnect with dimension-order XY routing, starvation-free round-robin arbitration, and credit-less ready/valid flow control.

Milestone v0.3.0 transitions FlexNoC from single-flit transactions to **wormhole multi-flit packet switching**, enabling high-bandwidth transfers of arbitrary packet lengths ($L \in [1, 16]$) while providing a clean architectural migration path for single-flit operations.

### Key Architectural Enhancements in v0.3.0:
1. **Flit Framing Protocol**: Exhaustive 2-bit mapping: `FLIT_HEAD` (`2'b00`), `FLIT_BODY` (`2'b01`), `FLIT_TAIL` (`2'b10`), and `FLIT_SINGLE` (`2'b11`).
2. **Payload Efficiency**: Body and Tail flits strip redundant routing coordinates, increasing raw payload capacity from 14 bits to **22 bits per flit (+57.1% payload efficiency)**.
3. **Canonical Egress Transfer Event**: Formally establishes `egress_handshake[o] = out_valid[o] && out_ready[o]` as the single authoritative event that advances packet counters and triggers reservation transitions.
4. **Decoupled Router Control**:
   - **Ingress Port Controller (IPC)**: Tracks per-ingress packet context, validates framing, latches routing decisions, and updates 5-bit flit counters using combinational next-state logic (`flit_count_next`).
   - **Egress Output Reservation Controller (ORC)**: Enforces atomic crossbar reservation locking, holds off competing inputs, and releases the lock upon `FLIT_TAIL`.
5. **Deadlock Freedom via Directed Channel Ranking**: Rigorous Channel Dependency Graph (CDG) analysis proving that a strictly increasing topological ranking function over all directed physical channels ($C_E, C_W, C_S, C_N, C_L$) mathematically guarantees zero circular wait.
6. **Coordinated Reset Architecture**: Single synchronous clock domain baseline with 6-phase coordinated reset sequencing and `mesh_ready` handshake.
7. **Starvation-Free Arbitration**: Precisely derived $\le 64$ handshake bound on each egress port under continuous contention with round-robin pointer advancement strictly upon packet completion.

---

## 2. Architectural Baseline & Backward Compatibility

### 2.1 Preserved Hardware Envelope
- **Topology**: Parameterized 2D Mesh grid ($M \times N$).
- **Clock Domain**: Single global synchronous clock domain (`clk`) across all mesh routers.
- **Port Allocation**: 5 logical ports per router (Local, North, East, South, West).
- **Routing Algorithm**: Deterministic dimension-order XY routing.
- **Physical Link Interface**: 32-bit synchronous `data`, `valid`, `ready` handshake.
- **Buffer Decoupling**: Ingress `push_ready = !full`, eliminating multi-hop combinational loops.

### 2.2 Backward Compatibility Analysis
A rigorous bit-level comparison between baseline v0.1.0/v0.2.0 and v0.3.0 reveals that the raw 32-bit vector format has changed:
- In v0.1.0, bits `[31:30]` carried `dest_x[1:0]`.
- In v0.3.0, bits `[31:30]` carry `flit_type[1:0]`.
- If an unmodified v0.1.0 packet targeting column 0 (`dest_x = 2'b00`) were injected into a v0.3.0 router, it would be decoded as `FLIT_HEAD` (`2'b00`), causing the router to lock its output port waiting for body/tail flits that never arrive.
- **Resolution**:
  1. FlexNoC v0.3.0 introduces an explicit protocol versioning boundary.
  2. Native single-flit transactions use `FLIT_SINGLE` (`2'b11`), which traverses the crossbar in a single cycle without locking.
  3. Legacy endpoints are supported via the synthesizable `flexnoc_v1_adapter` shim, which maps legacy signals into `FLIT_SINGLE`.

---

## 3. Packet Format & Canonical Handshake Semantics

Detailed layout is defined in [docs/architecture/FLEXNOC_V0.3.0_PACKET_FORMAT.md](FLEXNOC_V0.3.0_PACKET_FORMAT.md).

```
 31    30 29    28 27    26 25    24 23    22 21          14 13       10 9                         0
+--------+--------+--------+--------+--------+--------------+----------+-----------------------------+
| flit_ty| dest_x | dest_y | src_x  | src_y  |    pkt_id    | pkt_len  |        head_payload         |
| (2 b)  | (2 b)  | (2 b)  | (2 b)  | (2 b)  |    (8 b)     |  (4 b)   |           (10 b)            |
+--------+--------+--------+--------+--------+--------------+----------+-----------------------------+
  HEADER FLIT (flit_type = 2'b00)

 31    30 29          22 21                                                                        0
+--------+--------------+---------------------------------------------------------------------------+
| flit_ty|    pkt_id    |                               body_payload                                |
| (2 b)  |    (8 b)     |                                  (22 b)                                   |
+--------+--------------+---------------------------------------------------------------------------+
  BODY FLIT (flit_type = 2'b01)

 31    30 29          22 21                                                                        0
+--------+--------------+---------------------------------------------------------------------------+
| flit_ty|    pkt_id    |                               tail_payload                                |
| (2 b)  |    (8 b)     |                                  (22 b)                                   |
+--------+--------------+---------------------------------------------------------------------------+
  TAIL FLIT (flit_type = 2'b10)

 31    30 29    28 27    26 25    24 23    22 21          14 13                                     0
+--------+--------+--------+--------+--------+--------------+-----------------------------------------+
| flit_ty| dest_x | dest_y | src_x  | src_y  |    pkt_id    |                 payload                 |
| (2 b)  | (2 b)  | (2 b)  | (2 b)  | (2 b)  |    (8 b)     |                 (14 b)                  |
+--------+--------+--------+--------+--------+--------------+-----------------------------------------+
  SINGLE FLIT (flit_type = 2'b11)
```

### 3.1 Distinct Handshake Definitions & Synchronization
- **FIFO Enqueue**: $\text{fifo\_enqueue}[i] = \text{in\_valid}[i] \land \text{in\_ready}[i]$. Moves flit into input buffer. Zero impact on forwarding counter.
- **Canonical Egress Transfer**: $\text{egress\_handshake}[o] = \text{out\_valid}[o] \land \text{out\_ready}[o]$. The authoritative transfer event.
- **Counter Advance**: $\text{counter\_advance}[i] = \text{fifo\_valid}[i] \land \text{arb\_grant}[o][i] \land \text{egress\_handshake}[o]$. Advances `flit_count` to `flit_count_next` on `posedge clk`.
- **FIFO Dequeue**: In FWFT mode, $\text{fifo\_dequeue}[i] \equiv \text{egress\_handshake}[o]$, ensuring synchronized dequeue and departure.

---

## 4. Decoupled Router Control Architecture

Detailed state machines and synthesizable pseudocode are specified in [docs/architecture/FLEXNOC_V0.3.0_ROUTER_STATE_MACHINE.md](FLEXNOC_V0.3.0_ROUTER_STATE_MACHINE.md).

```
                      +----------------------------------+
                      |         ROUTER DATAPATH          |
                      +----------------------------------+
                                        |
                 +----------------------+----------------------+
                 |                                             |
                 v                                             v
+----------------------------------+         +----------------------------------+
|   Ingress Port Controller (IPC)  |         | Output Reserv. Controller (ORC)  |
|   - 1 per ingress port (x5)      |         | - 1 per egress port (x5)         |
|   - Tracks per-ingress context   |         | - Enforces atomic crossbar lock  |
|   - Latches route on FLIT_HEAD   |         | - Masks competing requests       |
|   - 5-bit flit_count_next logic  |         | - Releases lock on FLIT_TAIL     |
|   - Governs FIFO pop             |         | - Advances round-robin pointer   |
+----------------------------------+         +----------------------------------+
```

---

## 5. Directed-Channel Dependency & Provable Deadlock Freedom

### 5.1 Directed Physical Channel Ranking
Let all physical channels in an $M \times N$ mesh be partitioned into:
- Eastbound: $C_E = \{c_E(x, y) \mid 0 \le x < M-1, 0 \le y < N\}$
- Westbound: $C_W = \{c_W(x, y) \mid 1 \le x < M, 0 \le y < N\}$
- Southbound: $C_S = \{c_S(x, y) \mid 0 \le x < M, 0 \le y < N-1\}$
- Northbound: $C_N = \{c_N(x, y) \mid 0 \le x < M, 1 \le y < N\}$
- Local Ejection: $C_L = \{c_L(x, y) \mid 0 \le x < M, 0 \le y < N\}$

We assign each directed physical channel a strict topological rank:
$$\mathcal{R}(c_E(x, y)) = 1000 + x$$
$$\mathcal{R}(c_W(x, y)) = 1000 + (M - x)$$
$$\mathcal{R}(c_S(x, y)) = 2000 + y$$
$$\mathcal{R}(c_N(x, y)) = 2000 + (N - y)$$
$$\mathcal{R}(c_L(x, y)) = 3000$$

### 5.2 Strict Monotonicity Proof
Under deterministic XY routing:
- East progression: $\mathcal{R}(c_E(x, y)) < \mathcal{R}(c_E(x+1, y))$ because $x < x+1$.
- West progression: $\mathcal{R}(c_W(x, y)) < \mathcal{R}(c_W(x-1, y))$ because $M - x < M - (x-1)$.
- Turns from $X$ to $Y$: $\mathcal{R}(c_X) \in [1000, 1000+M] < \mathcal{R}(c_Y) \in [2000, 2000+N]$.
- South progression: $\mathcal{R}(c_S(x, y)) < \mathcal{R}(c_S(x, y+1))$ because $y < y+1$.
- North progression: $\mathcal{R}(c_N(x, y)) < \mathcal{R}(c_N(x, y-1))$ because $N - y < N - (y-1)$.
- Local ejection: $\mathcal{R}(c_X), \mathcal{R}(c_Y) < \mathcal{R}(c_L) = 3000$.
- Turns from $Y$ to $X$ are physically prohibited.

Every permitted dependency satisfies $\mathcal{R}(c_a) < \mathcal{R}(c_b)$. Thus, the directed Channel Dependency Graph is an Acyclic Directed Graph (DAG):
$$\text{Cycles}(CDG) = \emptyset$$

### 5.3 Extension to Wormhole Output Reservations
Wormhole packet locks hold chains of reservations $O(c_1) \prec O(c_2) \dots \prec O(c_k)$. Because the underlying channels are strictly ordered by $\mathcal{R}(c)$, circular wait of held and requested reservation locks cannot form.
*Rigor Statement*: Architectural mathematical proof based on Dally and Seitz's Theorem. Stated environmental assumptions: (1) Non-blocking sink consumption, (2) $L \le 16$, (3) sender completion.

---

## 6. Coordinated Network Reset Protocol (Single Clock Domain)

FlexNoC v0.3.0 operates within a **single global synchronous clock domain** (`clk`). Multi-clock domain crossings (CDC) and asynchronous mesh boundaries are excluded from the v0.3.0 baseline.

### 6-Phase Reset Protocol:
1. **Phase 1: Ingress Quiescence**: Reset controller asserts `stop_injection = 1` to all Network Interfaces.
2. **Phase 2: Synchronous Reset Assertion**: Synchronous active-low `rst_n = 0` asserted for $N_{\text{rst}} \ge 8$ clock cycles across all mesh routers.
3. **Phase 3: Synchronous Clearing**: In all routers, all ORCs, IPCs, and input FIFOs reset to initial states (`IPC_IDLE`, pointers = 0).
4. **Phase 4: Synchronous Reset Release**: `rst_n = 1` released synchronously on a clock posedge across all routers.
5. **Phase 5: Reset Completion Handshake (`mesh_ready`)**:
   - Each router asserts `router_ready` when reset is released and all buffers are cleared:
     $$\text{router\_ready} = \text{rst\_n} \land (\forall o: !\text{output\_locked}[o]) \land (\forall i: !\text{fifo\_valid}[i] \land \text{ipc\_state}[i] == \text{IPC\_IDLE})$$
   - Top-level aggregates: `mesh_ready = &router_ready[0:M*N-1]`.
6. **Phase 6: Traffic Resumption**: Traffic injection is unblocked (`stop_injection = 0`) **if and only if `mesh_ready == 1`**.

---

## 7. Fairness and Starvation Bounds

FlexNoC distinguishes between three operational regimes:
- **Property A (Arbitration Fairness on Egress Port $o$)**: Pointer advances on `FLIT_TAIL`. Service duration $\le 16$ handshakes. Waiting time for any competing input:
  $$W_{\text{handshakes}}(o) \le (N - 1) \times L_{\max} = 4 \times 16 = 64 \text{ successful flit handshakes on egress port } o$$
- **Property B (Progress under Bounded Stalls)**: If downstream stall per flit is bounded by $S_{\max}$ cycles, packet latency is bounded by $L \times (1 + S_{\max})$, and wait time is bounded by $64 \times (1 + S_{\max})$ cycles.
- **Property C (General Liveness)**: In the presence of infinite downstream backpressure or sender stalls, progress is suspended without breaking lock mutual exclusion. Recovery is initiated via coordinated reset.

---

## 8. Verification & Implementation Roadmap

Full test matrix (TC-MF-01 through TC-MF-30), scoreboard architecture, and measurable criteria are documented in [docs/architecture/FLEXNOC_V0.3.0_VERIFICATION_PLAN.md](FLEXNOC_V0.3.0_VERIFICATION_PLAN.md).

```mermaid
flowchart LR
    M0["M0: Protocol Freeze"] --> M1["M1: Framing & Package"]
    M1 --> M2["M2: Output Reservation"]
    M2 --> M3["M3: Router Integration"]
    M3 --> M4["M4: Mesh Integration"]
    M4 --> M5["M5: Multi-Flit Verification"]
    M5 --> M6["M6: Performance Sweeps"]
    M6 --> M7["M7: Synthesis & Release"]
```

| Milestone | Target Objective | Deliverables | Acceptance Criteria |
| :--- | :--- | :--- | :--- |
| **M0** | Specification Freeze | Approved architecture specs in `docs/architecture/` | Review completed; zero ambiguities |
| **M1** | Framing & Package | Update `rtl/common/flexnoc_pkg.sv` | Verilator lint clean; unit framing tests pass |
| **M2** | Output Reservation | ORC reservation lock logic in `flexnoc_router.sv` | Zero interleaving in unit router tests |
| **M3** | Router Multi-Flit | Full IPC FSM and route retention in `flexnoc_router` | Multi-flit packets pass single router |
| **M4** | Mesh Integration | Multi-flit wormhole routing in `mesh_top` (2x2 & 4x4) | Multi-hop multi-flit packets delivered |
| **M5** | Verification & Stress | 256 all-pairs multi-flit regression, scoreboard checks | 100% tests pass; zero interleaving detected |
| **M6** | Performance Sweeps | Variable length sweeps ($L=1,2,4,8$) across workloads | Saturation curves and CSV exported |
| **M7** | Synthesis & Release | Yosys gate synthesis, lint clean, v0.3.0 release report | Zero latches, linear scaling confirmed |
