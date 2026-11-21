# FlexNoC v0.3.0 — Multi-Flit Architecture Design Review & Technical Audit

- **Review Milestone**: v0.3.0 Specification Review and Correction Pass
- **Review Date**: 2026-11-21
- **Review Status**: **APPROVED — READY FOR M1 IMPLEMENTATION**
- **Reviewers**: FlexNoC Independent Architecture & Verification Review Board
- **Associated Documents**:
  - [docs/architecture/FLEXNOC_V0.3.0_MULTI_FLIT_SPEC.md](FLEXNOC_V0.3.0_MULTI_FLIT_SPEC.md)
  - [docs/architecture/FLEXNOC_V0.3.0_PACKET_FORMAT.md](FLEXNOC_V0.3.0_PACKET_FORMAT.md)
  - [docs/architecture/FLEXNOC_V0.3.0_ROUTER_STATE_MACHINE.md](FLEXNOC_V0.3.0_ROUTER_STATE_MACHINE.md)
  - [docs/architecture/FLEXNOC_V0.3.0_VERIFICATION_PLAN.md](FLEXNOC_V0.3.0_VERIFICATION_PLAN.md)
  - [docs/architecture/FLEXNOC_V0.3.0_FINAL_CONSISTENCY_AUDIT.md](FLEXNOC_V0.3.0_FINAL_CONSISTENCY_AUDIT.md)

---

## 1. Executive Summary & Review Scope

An independent architectural design review was conducted on the proposed specifications for **FlexNoC v0.3.0 Multi-Flit Packet Architecture**. The review systematically analyzed the hardware control mechanisms, packet framing formats, flow control, arbitration fairness, deadlock safety, backward compatibility, counter sizing, canonical transfer events, and verification strategies.

This document records the formal findings, architectural critiques, resolved design decisions, updated state machine and protocol rules, mathematical proofs of mutual exclusion and deadlock freedom, and the final recommendation for implementation gating.

---

## 2. Review Findings & Defect Critique

### Finding 1: Ingress vs Egress Transfer Event Disambiguation
- *Issue*: Conflating ingress link acceptance (`in_valid && in_ready`) with egress crossbar departure (`out_valid && out_ready`) created the potential for counter double-counting or drift.
- *Correction*: Formally established `egress_handshake[o] = out_valid[o] && out_ready[o]` as the single canonical transfer event. Ingress FIFO enqueue does not advance forwarding counters. In FWFT mode, FIFO dequeue and egress handshake occur on the exact same clock edge.

### Finding 2: Directed Channel Dependency & Deadlock Rigor
- *Issue*: Partitioning channels merely into coarse sets ($C_X, C_Y, C_L$) failed to prove that dependencies within horizontal or vertical dimensions were acyclic.
- *Correction*: Established a formal topological ranking function $\mathcal{R}(c)$ over every individual directed channel ($c_E, c_W, c_S, c_N, c_L$). Proved that every permitted turn in dimension-order XY routing strictly increases channel rank, mathematically guaranteeing that the directed Channel Dependency Graph is a DAG ($\text{Cycles}(CDG) = \emptyset$).

### Finding 3: Tail Counter Next-State Validation Semantics
- *Issue*: Comparing registered `flit_count` upon `FLIT_TAIL` introduces a 1-cycle lag because registers update on `posedge clk`.
- *Correction*: Defined explicit combinational `flit_count_next` logic. Length validation evaluates `flit_count_next == decoded_len` in the same cycle as the tail transfer.

### Finding 4: Unsafe Isolated Local Reset in Multi-Router Wormhole Paths
- *Issue*: Applying a reset only to an intermediate router $R_1$ while a wormhole packet spans $R_0 \rightarrow R_1 \rightarrow R_2$ clears $R_1$'s reservation, leaving $R_0$ still locked to East (causing orphan flits at $R_1$) and $R_2$ still locked to Local (causing permanent starvation at $R_2$).
- *Correction*: Baseline recovery strictly mandates **Coordinated Network Reset**, where injection is halted, a synchronous reset pulse is asserted across all mesh routers simultaneously, and traffic resumes only after `mesh_ready == 1`.

---

## 3. Formal Resolutions & Architectural Decisions

### Resolution 1: Canonical Egress Handshake Accounting
- Canonical transfer: `egress_handshake[o] = out_valid[o] && out_ready[o]`.
- Counter advancement: `counter_advance[i] = fifo_valid[i] && arb_grant[o][i] && egress_handshake[o]`.
- Synchronous FWFT dequeue: `fifo_dequeue[i] == egress_handshake[o]`.

### Resolution 2: Directed Channel Ranking $\mathcal{R}(c)$
- Eastbound: $\mathcal{R}(c_E(x, y)) = 1000 + x$
- Westbound: $\mathcal{R}(c_W(x, y)) = 1000 + (M - x)$
- Southbound: $\mathcal{R}(c_S(x, y)) = 2000 + y$
- Northbound: $\mathcal{R}(c_N(x, y)) = 2000 + (N - y)$
- Local Ejection: $\mathcal{R}(c_L(x, y)) = 3000$
- Every valid turn strictly increases rank $\implies$ DAG $\implies$ zero circular wait.

### Resolution 3: Coordinated Reset Model (Single Clock Domain)
- Single synchronous clock domain baseline for v0.3.0.
- Centralized Reset Controller coordinates: Quiesce $\to$ 8-cycle assert $\to$ clear $\to$ synchronous release $\to$ `mesh_ready` handshake $\to$ resume traffic.

---

## 4. Updated State Machines & Atomic Reservation Semantics

### 4.1 Cycle-by-Cycle Reservation Walkthrough
- **Cycle $T$ (Arbitration)**: Output $o$ is unlocked. Ingress $i$ presents `FLIT_HEAD`; round-robin arbiter evaluates combinational and grants input $i$. Competing requests are denied.
- **Clock Edge $T \rightarrow T+1$ (Lock Acquisition)**: Downstream `out_ready[o] == 1`. At `posedge clk`:
  $$\text{output\_locked}[o] \le 1'b1; \quad \text{locked\_owner}[o] \le i;$$
- **Cycles $T+1 \dots T+K$ (Body Streaming)**: Crossbar is hard-wired to `locked_owner[o] = i`. Competing inputs are completely masked out.
- **Clock Edge $T+M \rightarrow T+M+1$ (Lock Release)**: `FLIT_TAIL` handshakes. At `posedge clk`:
  $$\text{output\_locked}[o] \le 1'b0; \quad \text{locked\_owner}[o] \le 3'\text{d0}; \quad \text{priority\_ptr}[o] \le (i + 1) \pmod 5;$$

### 4.2 Mathematical Proof of Mutual Exclusion
1. In cycle $T$, arbiter grant is strictly one-hot: $\sum_k \text{grant}[o][k] \le 1$. Hence, $\forall j \ne i, \text{grant}[o][j] = 0$.
2. At the exact clock edge of header acceptance, `output_locked[o]` is sequentially asserted to 1, registering `locked_owner[o] = i`.
3. In all subsequent cycles while locked, grant generation logic forces `grant[o] = (5'b1 << locked_owner[o])`, bypassing arbitration.
4. Therefore, no competing input $j$ can ever transfer data onto output $o$ either in cycle $T$ (lost arbitration) or in cycles $T+1 \dots T+M$ (masked by lock). Interleaving is impossible.

---

## 5. Deadlock & Fairness Formal Analysis

### 5.1 Channel Dependency Graph (CDG) & Deadlock Freedom
- Every individual directed channel in $C_E, C_W, C_S, C_N, C_L$ has a strictly monotonic ranking $\mathcal{R}(c)$.
- All valid XY routing transitions strictly increase $\mathcal{R}(c)$. Vertical-to-horizontal turns are physically disabled.
- The directed Channel Dependency Graph is an Acyclic Directed Graph (DAG):
  $$\text{Cycles}(CDG) = \emptyset$$
- Because wormhole reservations are acquired strictly along the DAG topological order ($C_X \prec C_Y \prec \text{Local}$), circular wait of held and requested reservation locks cannot form.
- *Architectural Rigor Statement*: Architectural mathematical proof based on Dally-Seitz topological ordering under the explicit assumptions of non-blocking sink consumption, $L \le 16$, and sender tail completion.

### 5.2 Starvation Freedom & Fairness Proof
- Round-robin pointer advances strictly on `FLIT_TAIL` (or `FLIT_SINGLE`).
- Maximum service duration per packet is 16 handshakes ($L \le 16$).
- On any egress port $o$, an ingress port waits at most:
  $$W_{\text{handshakes}}(o) \le (N - 1) \times L_{\max} = 4 \times 16 = 64 \text{ flit handshakes on that egress port}$$
  before its header is granted. Starvation is mathematically impossible under active forward progress.

---

## 6. Final Review Board Recommendation

The independent design review confirms that all architectural ambiguities, length counter sizing, clock-edge timings, canonical transfer events, directed channel rankings, coordinated reset recovery, state machines, and deadlock/fairness proofs have been rigorously resolved.

**Final Recommendation**:

$$\Huge \textbf{A. Ready for M1 implementation.}$$

The specifications in `docs/architecture/` are complete, mathematically sound, verified for safety, and approved as the implementation baseline for FlexNoC v0.3.0.
