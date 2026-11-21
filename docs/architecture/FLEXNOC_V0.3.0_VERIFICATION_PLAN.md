# FlexNoC v0.3.0 — Multi-Flit Verification Plan & Test Strategy

- **Document Version**: 2.4 (Channel Dependency & Canonical Transfer Semantics Pass)
- **Status**: **APPROVED VERIFICATION SPECIFICATION**
- **Target Release**: FlexNoC v0.3.0
- **Authors**: FlexNoC Hardware Verification Team
- **Associated Documents**:
  - [docs/architecture/FLEXNOC_V0.3.0_MULTI_FLIT_SPEC.md](FLEXNOC_V0.3.0_MULTI_FLIT_SPEC.md)
  - [docs/architecture/FLEXNOC_V0.3.0_PACKET_FORMAT.md](FLEXNOC_V0.3.0_PACKET_FORMAT.md)
  - [docs/architecture/FLEXNOC_V0.3.0_ROUTER_STATE_MACHINE.md](FLEXNOC_V0.3.0_ROUTER_STATE_MACHINE.md)
  - [docs/architecture/FLEXNOC_V0.3.0_DESIGN_REVIEW.md](FLEXNOC_V0.3.0_DESIGN_REVIEW.md)
  - [docs/architecture/FLEXNOC_V0.3.0_FINAL_CONSISTENCY_AUDIT.md](FLEXNOC_V0.3.0_FINAL_CONSISTENCY_AUDIT.md)

---

## 1. Overview & Verification Strategy

The FlexNoC v0.3.0 verification environment extends the self-checking framework established in v0.1.0/v0.2.0. The mission is to prove that **multi-flit packets are transmitted atomically, routed correctly, arbitrated fairly, and protected from crossbar interleaving**, while validating backward compatibility, next-state counter update semantics (`flit_count_next`), canonical transfer event decoupling (`egress_handshake` vs `fifo_enqueue`), framing anomaly resilience across all 9 conditions (`ANOM-01` through `ANOM-09`), directed channel rank monotonicity, and coordinated multi-router reset recovery.

### Core Verification Invariants:
1. **Flit Interleaving Zero-Tolerance**: Once a header flit is accepted on an output port, all subsequent flits emerging on that port must match that packet's transaction ID (`pkt_id`) until the tail flit departs.
2. **Canonical Transfer Decoupling**: An input FIFO enqueue (`in_valid && in_ready`) must **never** advance the packet forwarding counter; only an egress handshake (`out_valid && out_ready`) advances `flit_count`.
3. **Synchronous FWFT Dequeue**: Ingress FIFO pop (`fifo_rd_en`) and egress handshake occur on the exact same clock edge.
4. **Counter & Next-State Boundary Safety**: 5-bit counters must cleanly count to 16 using `flit_count_next` without overflow, wrapping, or false early-tail flags.
5. **Channel Rank Monotonicity**: Every traversed physical channel along any route strictly increases the topological ranking function $\mathcal{R}(c)$.
6. **Framing Robustness**: All 9 anomaly conditions (`ANOM-01` to `ANOM-09`) must be trapped with explicit error flags without corrupting unrelated traffic.
7. **Coordinated Reset Cleanliness**: Network reset must purge in-flight packet locks across all routers cleanly, completing with the `mesh_ready` handshake.

---

## 2. Comprehensive Test Matrix & Measurable Pass/Fail Criteria

| Test ID | Test Scenario | Description & Stimulus | Anomaly / Rule Mapped | Measurable Pass/Fail Criteria |
| :--- | :--- | :--- | :---: | :--- |
| **TC-MF-01** | **Single-Flit Compatibility** | Sweep 256 all-pairs in 4x4 mesh using `FLIT_SINGLE` packets ($L=1$). | Protocol Grammar | 100% packets delivered; 0 interleaving errors; latencies match v0.2.0 baseline. |
| **TC-MF-02** | **Minimal Multi-Flit (2 Flits)** | Inject 2-flit packets (`HEAD` + `TAIL`, $L=2$) across all 256 node pairs. | Protocol Grammar | All 256 packets reassembled; lock held for exactly 2 transfers; 0 assertions. |
| **TC-MF-03** | **Variable-Length Sweep** | Sweep packet lengths $L \in [2, 16]$ across random source/destination pairs. | Length Encoding | Ejected flit count strictly equals $L$; `pkt_len` matches; payload bits match 100%. |
| **TC-MF-04** | **Atomic Reservation Acquisition** | Ingress 0 presents `FLIT_HEAD` to East output; check lock timing in single-router TB. | Clock-Edge Lock | `output_locked` asserts on same clock edge as header handshake; 0 unreserved cycles. |
| **TC-MF-05** | **Same-Output Competing Headers** | Ingress 0 and Ingress 1 both present `FLIT_HEAD` targeting East output simultaneously. | Mutual Exclusion / `ANOM-07` | Winner transmits all $L$ flits consecutively; loser flits held in FIFO; **0 crossbar interleaving**. |
| **TC-MF-06** | **Back-to-Back Header-to-Body** | Ingress 0 streams `HEAD` followed immediately by `BODY` flits in consecutive cycles (no bubbles). | Pipelined Transfer | Crossbar sustains 1 flit/cycle throughput; grant remains locked to Ingress 0. |
| **TC-MF-07** | **Tail Handshake Under Backpressure** | Downstream receiver deasserts `out_ready` for 20 cycles while `FLIT_TAIL` is at output. | Stall Stability | `output_locked` remains 1 during stall; clears exactly 1 cycle after `out_ready` asserted. |
| **TC-MF-08** | **Multiple Packets From One Ingress** | Ingress 0 sends Packet A ($L=4$) followed immediately by Packet B ($L=3$). | IPC Sequencing | Packet A completes cleanly; Packet B arbitrates and acquires new lock; 0 data corruption. |
| **TC-MF-09** | **Multi-Hop Reservation Lifecycle** | 3-router wormhole traversal ($R_0 \rightarrow R_1 \rightarrow R_2$). Track lock timing at all 3 routers. | Multi-Hop Locking | Locks acquire sequentially ($R_0 \rightarrow R_1 \rightarrow R_2$); release sequentially upon tail departure. |
| **TC-MF-10** | **Intermediate-Router Stall** | During a 3-router wormhole transfer, $R_2$ asserts backpressure for 50 cycles. | Backpressure | Upstream FIFOs buffer flits; all 3 router reservations hold lock; transfer resumes cleanly. |
| **TC-MF-11A**| **Framing: Early TAIL** | Inject packet with declared $L=6$, but inject `FLIT_TAIL` on flit #3. | `ANOM-01` | ORC releases lock immediately upon tail; scoreboard traps `ERR_PREMATURE_TAIL`. |
| **TC-MF-11B**| **Framing: Missing TAIL** | Inject declared $L=4$, but inject `FLIT_BODY` instead of `FLIT_TAIL` on flit #4. | `ANOM-02` | Scoreboard flags `ERR_MISSING_TAIL`; router holds lock until watchdog expires. |
| **TC-MF-11C**| **Framing: Excess BODY Flits** | Inject declared $L=3$, followed by 5 additional `FLIT_BODY` flits before `FLIT_TAIL`. | `ANOM-03` | Scoreboard traps `ERR_EXCESS_BODY`; lock maintained; released upon final tail. |
| **TC-MF-11D**| **Framing: Orphan & Bad Flits** | Ingress receives orphan flits (`ANOM-04/05`), unexpected head (`ANOM-06`), or bad dest (`ANOM-08`). | `ANOM-04/05/06/08/09` | IPC flags `status_framing_err`; flit does NOT lock network output; router does not crash. |
| **TC-MF-12** | **Mid-Flight Asynchronous Reset** | Inject 8-flit packets across mesh; assert `rst_n = 0` while flits are distributed. | Reset Recovery | All routers clear `output_locked` to 0; post-reset packets route with 100% success. |
| **TC-MF-13** | **Watchdog Hang Detection** | Lock output reservation and hold downstream `out_ready = 0` for $>10,000$ cycles. | Watchdog Counter | `status_hang_alert` asserts; router maintains lock; does not corrupt other ports. |
| **TC-MF-14** | **No Premature Unlock** | Multi-flit packet with intermittent sender bubbles (FIFO temporarily empty mid-packet). | Bubble Invariance | `output_locked` remains 1 during bubbles; competing inputs cannot usurp output. |
| **TC-MF-15** | **Legacy Adapter Verification** | Feed v0.1.0 32-bit packets into `flexnoc_v1_adapter`; verify output in v0.3.0 mesh. | Backward Compat | Adapter correctly prepends `2'b11`; packets traverse mesh as valid `FLIT_SINGLE`. |
| **TC-MF-16** | **Maximum 16-Flit Packet Boundary** | Inject packet with maximum length $L=16$ (Head, 14 Bodies, Tail). | Length Boundary | `flit_count_next` evaluates to 16 (`5'b10000`) on tail; 0 overflow; clean match. |
| **TC-MF-17** | **Counter Saturation & Overflow** | Inject malformed packet with 35 continuous `FLIT_BODY` flits. | Counter Saturation / `ANOM-03` | `flit_count_next` increments to 31 (`5'b11111`) and saturates without wrapping to 0. |
| **TC-MF-18** | **Early TAIL Recovery Verification** | Inject Early TAIL ($L_{\text{decl}}=8, L_{\text{actual}}=3$). Follow immediately with normal packet. | `ANOM-01` Recovery | Lock released on cycle 3; subsequent packet arbitrates and routes without hang. |
| **TC-MF-19** | **Missing TAIL Watchdog Verification** | Sender stops sending at flit 3 of 8-flit packet; observe for $T_{\text{hang}}$ cycles. | `ANOM-02` Detection | `status_hang_alert` asserts at cycle 10,000; lock remains stable (no auto-unlock). |
| **TC-MF-20** | **Local Reset Hazard Demonstration** | In a 3-router wormhole chain, assert reset *only* to middle router $R_1$. | Reset Hazard | Confirms upstream $R_0$ and downstream $R_2$ enter corrupt states; verifies hazard. |
| **TC-MF-21** | **Coordinated Multi-Router Reset** | Assert synchronized 8-cycle `rst_n` pulse to entire mesh during multi-flit transfers. | Coordinated Reset | All routers clear locks and FIFOs; post-reset all-pairs test passes 100%. |
| **TC-MF-22** | **Neighbor Reservation Cleanup** | Measure neighbor lock registers during coordinated reset sequence. | Reset Handshake | `mesh_ready` asserts; all `output_locked` signals deassert to 0 simultaneously. |
| **TC-MF-23** | **Bounded Progress Under Stalls** | Downstream receiver applies pseudo-random backpressure ($S \in [1, 50]$ cycles/flit). | Bounded Liveness | All multi-flit packets complete within $L \times (1 + S_{\max})$ bound; zero flit loss. |
| **TC-MF-24** | **Arbitration Fairness Verification** | All 5 ingress ports continuously inject 16-flit packets to same egress port. | Fairness Bound | Every port granted within $\le 64$ handshakes on egress port; grant distribution variance $< 2\%$. |
| **TC-MF-25** | **Ingress Enqueue Isolation** | Ingress accepts flits (`in_valid && in_ready`), but egress is stalled (`out_ready = 0`). | Transfer Decoupling | `flit_count` strictly remains 0; FIFO enqueue never advances forwarding counter. |
| **TC-MF-26** | **Output Backpressure Stability** | Egress `out_ready` held LOW for 40 cycles mid-packet with flit waiting at FIFO head. | Stall Invariance | `flit_count` holds exact value; 0 counter drift over 40 stalled cycles. |
| **TC-MF-27** | **Single Handshake Unit Increment** | Downstream receiver asserts single-cycle `out_ready` pulse during active transfer. | Unit Counting | `flit_count` increments by exactly 1 on `posedge clk`; no double increment. |
| **TC-MF-28** | **Synchronized Dequeue and Egress Acceptance** | Monitor asserts both signals concurrently during high-throughput streaming. | FWFT Synchronization | `fifo_rd_en[i]` and `egress_handshake[o]` assert on identical clock edge 100% of time. |
| **TC-MF-29** | **No Duplicate Counter Update** | Burst of 8 enqueue operations followed by burst of 8 egress handshakes. | Accounting Integrity | `flit_count` equals 8 at end of sequence; zero extra or missed count increments. |
| **TC-MF-30** | **Directed Channel Rank Verification** | Scoreboard logs channel sequence for all routes in 2x2 and 4x4 meshes. | CDG Monotonicity | For every hop $(c_a \to c_b)$, $\mathcal{R}(c_a) < \mathcal{R}(c_b)$ is strictly verified. |

---

## 3. Scoreboard Architecture & Invariant Checkers

```
                +------------------------------------+
                |  Verification Invariant Checker    |
                +------------------------------------+
                                  |
         +------------------------+------------------------+
         |                        |                        |
         v                        v                        v
+------------------+     +------------------+     +------------------+
| Crossbar Guard   |     | Packet Reassembly|     | Channel Rank     |
| Check for zero   |     | Check payload &  |     | Monotonicity     |
| interleaving     |     | flit_count_next  |     | Checker R(c)     |
+------------------+     +------------------+     +------------------+
```

### 3.1 Dedicated Crossbar Interleaving Guard
On every router crossbar egress monitor:
```systemverilog
always @(posedge clk) begin
    if (rst_n && out_valid[o] && out_ready[o]) begin
        if (out_data[o][31:30] == FLIT_HEAD) begin
            active_pkt_id[o] <= out_data[o][21:14];
            in_packet[o]     <= 1'b1;
        end else if (in_packet[o]) begin
            assert (out_data[o][29:22] == active_pkt_id[o])
                else $fatal(1, "[FATAL] Crossbar interleaving on Egress Port %0d! Expected Pkt 0x%0h, Got 0x%0h",
                            o, active_pkt_id[o], out_data[o][29:22]);
            if (out_data[o][31:30] == FLIT_TAIL) begin
                in_packet[o] <= 1'b0;
            end
        end
    end
end
```

### 3.2 Packet Reassembler Scoreboard
1. **Header Registration**: Upon `FLIT_HEAD`, scoreboard opens a new packet record indexed by `{src_node, pkt_id}`. Latches 5-bit decoded length $L_{\text{decl}} = \{1'b0, \text{wire\_len}\} + 5'd1$.
2. **Payload Concatenation**: Appends payloads from `FLIT_HEAD`, each `FLIT_BODY`, and `FLIT_TAIL` into a dynamic payload byte stream.
3. **Tail Comparison**: Upon `FLIT_TAIL`, verifies `flit_count_next == decoded_len` in the same cycle.
4. **Latency Verification**: Transit latency $T_{\text{latency}} = T_{\text{eject}} - T_{\text{inject}}$ falls within theoretical bounds:
   $$T_{\text{latency}} \ge H(src, dst) + (L - 1)$$
