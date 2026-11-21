# FlexNoC v0.3.0 — Router Control State Machine & Output Reservation Specification

- **Document Version**: 2.4 (Channel Dependency & Canonical Transfer Semantics Pass)
- **Status**: **APPROVED ARCHITECTURE SPECIFICATION**
- **Target Release**: FlexNoC v0.3.0
- **Authors**: FlexNoC Architecture, Verification, and Synthesis Teams
- **Associated Documents**:
  - [docs/architecture/FLEXNOC_V0.3.0_MULTI_FLIT_SPEC.md](FLEXNOC_V0.3.0_MULTI_FLIT_SPEC.md)
  - [docs/architecture/FLEXNOC_V0.3.0_PACKET_FORMAT.md](FLEXNOC_V0.3.0_PACKET_FORMAT.md)
  - [docs/architecture/FLEXNOC_V0.3.0_VERIFICATION_PLAN.md](FLEXNOC_V0.3.0_VERIFICATION_PLAN.md)
  - [docs/architecture/FLEXNOC_V0.3.0_DESIGN_REVIEW.md](FLEXNOC_V0.3.0_DESIGN_REVIEW.md)
  - [docs/architecture/FLEXNOC_V0.3.0_FINAL_CONSISTENCY_AUDIT.md](FLEXNOC_V0.3.0_FINAL_CONSISTENCY_AUDIT.md)

---

## 1. Overview & Decoupled Controller Architecture

FlexNoC v0.3.0 implements wormhole multi-flit switching by decoupling control into two independent, orthogonal state-tracking structures:
1. **Ingress Port Controller (IPC)**: Instantiated once per ingress port ($i \in [0, 4]$). Maintains per-ingress packet context, validates framing, latches routing decisions from `FLIT_HEAD`, tracks received flit counts using combinational next-state logic (`flit_count_next`), and coordinates FIFO read enables.
2. **Egress Output Reservation Controller (ORC)**: Instantiated once per egress port ($o \in [0, 4]$). Evaluates requests from IPCs, locks crossbar output multiplexers for the duration of a multi-flit packet, enforces strict mutual exclusion against competing inputs, and advances the round-robin priority pointer upon tail flit handshake.

```
       +-------------------------------------------------------------+
       |                     FLEXNOC ROUTER                          |
       |                                                             |
       |  Ingress Port i                                             |
       |  +------------+      +-------------------+                  |
       |  | Input FIFO |----->| Ingress Port      |-- req[o][i] ----+ |
       |  +------------+      | Controller (IPC)  |                 | |
       |                      +-------------------+                 | |
       |                                                            | |
       |  Egress Port o                                             | |
       |                      +-------------------+                 | |
       |                      | Output Reserv.    |<----------------+ |
       |                      | Controller (ORC)  |                   |
       |                      +---------+---------+                   |
       |                                |                             |
       |                                v                             |
       |                      +-------------------+                   |
       |                      | 5x5 Crossbar Mux  |====> out_data[o]  |
       |                      +-------------------+                   |
       +-------------------------------------------------------------+
```

---

## 2. Canonical Transfer Events & Synchronization

FlexNoC strictly differentiates between ingress buffer enqueue and crossbar egress forwarding to prevent double-counting or skipping of flits.

### 2.1 Distinct Handshake Definitions

| Signal Name | Formal Boolean Definition | Operational Semantics | Counter / Reservation Impact |
| :--- | :--- | :--- | :--- |
| **`fifo_enqueue[i]`** | `in_valid[i] && in_ready[i]` | Link acceptance into Ingress FIFO $i$ | Pushes flit to FIFO buffer; **zero** effect on forwarding counter or output reservations. |
| **`fifo_dequeue[i]`** | `fifo_rd_en[i] = fifo_valid[i] && arb_grant[o][i] && out_ready[o]` | Pop from head of Ingress FIFO $i$ | Pops current flit; synchronous with `egress_handshake[o]` in FWFT datapath. |
| **`egress_handshake[o]`** | `out_valid[o] && out_ready[o]` | **CANONICAL EVENT**: Transfer through crossbar output $o$ | Advances `flit_count`; triggers reservation lock/release. |
| **`counter_advance[i]`** | `fifo_valid[i] && arb_grant[o][i] && egress_handshake[o]` | Forwarding counter increment in IPC $i$ | Increments `flit_count` to `flit_count_next` on `posedge clk`. |
| **`res_acquire[o]`** | `!output_locked[o] && egress_handshake[o] && (type == FLIT_HEAD)` | Output reservation acquisition | Asserts `output_locked[o] <= 1; locked_owner[o] <= i;` |
| **`res_release[o]`** | `output_locked[o] && egress_handshake[o] && (type == FLIT_TAIL)` | Output reservation release | Asserts `output_locked[o] <= 0; locked_owner[o] <= 0;` |

### 2.2 FWFT Ingress Dequeue and Egress Handshake Synchronization
Because FlexNoC utilizes First-Word-Fall-Through (FWFT) FIFOs and a purely combinational crossbar switch multiplexer, the data at the head of the FIFO is presented directly to the crossbar input pins without an intermediate register stage.
Consequently:
$$\text{fifo\_dequeue}[i] \equiv \text{egress\_handshake}[o] \quad (\text{where } o = \text{active\_out}[i] \land \text{arb\_grant}[o][i] == 1)$$
Both events occur on the **exact same clock edge**. This mathematical identity proves that:
1. An incoming flit entering the FIFO cannot prematurely advance the forwarding counter.
2. A forwarded flit is dequeued from the FIFO and accepted downstream simultaneously, preventing double-counting.
3. If downstream deasserts `out_ready[o]`, both `fifo_dequeue[i]` and `counter_advance[i]` are inhibited in the exact same cycle.

---

## 3. Per-Ingress Packet Context & Next-State Counter Semantics

### 3.1 Ingress Context Register Definition

```systemverilog
typedef enum logic [2:0] {
    IPC_IDLE   = 3'b000, // FIFO empty or awaiting new packet
    IPC_HEADER = 3'b001, // Header present at FIFO head, computing route and requesting ORC
    IPC_BODY   = 3'b010, // Multi-flit packet locked; streaming body flits
    IPC_TAIL   = 3'b011, // Final flit at head of FIFO; requesting release handshake
    IPC_ERROR  = 3'b100  // Framing anomaly detected; holding diagnostic alert
} ipc_state_e;

typedef struct {
    ipc_state_e        state;              // Ingress FSM state
    logic [1:0]        dest_x;             // Latched destination X coordinate
    logic [1:0]        dest_y;             // Latched destination Y coordinate
    logic [4:0]        latched_route;      // One-hot egress port vector (Local, N, E, S, W)
    logic [7:0]        pkt_id;             // Latched 8-bit transaction identifier
    logic [4:0]        decoded_len;        // 5-bit decoded packet length: {1'b0, wire_len} + 5'd1
    logic [4:0]        flit_count;         // 5-bit received flit counter (counts 1..31, saturates at 31)
    logic              framing_valid;      // 1 if packet adheres to grammatical flit sequence
    logic [2:0]        active_output;      // Index of currently targeted egress port [0..4]
} ingress_context_t;
```

### 3.2 Combinational Next-State Counter Logic (`flit_count_next`)

```systemverilog
always_comb begin
    flit_count_next[i] = flit_count[i];
    if (fifo_valid[i] && (arb_grant[active_out[i]][i] && out_ready[active_out[i]])) begin
        case (fifo_data[i][31:30]) // flit_type
            FLIT_HEAD:   flit_count_next[i] = 5'd1;
            FLIT_BODY:   flit_count_next[i] = (flit_count[i] == 5'd31) ? 5'd31 : (flit_count[i] + 5'd1);
            FLIT_TAIL:   flit_count_next[i] = (flit_count[i] == 5'd31) ? 5'd31 : (flit_count[i] + 5'd1);
            FLIT_SINGLE: flit_count_next[i] = 5'd1;
            default:     flit_count_next[i] = flit_count[i];
        endcase
    end
end
```

---

## 4. Reservation Lifecycle State Consistency Verification

We verify the exact clock-edge transitions and state consistency across nine critical lifecycle cases:

| Case # | Scenario Description | Pre-Conditions | Canonical Event (`egress_handshake`) | Clock Edge State Updates (`posedge clk`) | Mutual Exclusion / Consistency Guarantee |
| :---: | :--- | :--- | :---: | :--- | :--- |
| **Case 1** | **HEAD on Unlocked Output** | `output_locked=0`, `type=HEAD` | `out_valid && out_ready == 1` | `output_locked <= 1; locked_owner <= i; priority_ptr` unchanged; `flit_count <= 1; decoded_len <= len; ipc_state <= IPC_BODY;` | Output locked atomically on acceptance edge; zero unreserved cycle gap. |
| **Case 2** | **BODY while Locked** | `output_locked=1`, `owner=i`, `type=BODY` | `out_valid && out_ready == 1` | `output_locked <= 1; flit_count <= flit_count_next;` | Crossbar hard-wired to owner; competing inputs masked. |
| **Case 3** | **Correct TAIL Accepted** | `output_locked=1`, `owner=i`, `type=TAIL`, `flit_count_next == decoded_len` | `out_valid && out_ready == 1` | `output_locked <= 0; locked_owner <= 0; priority_ptr <= (i+1)%5; ipc_state <= IPC_IDLE; flit_count <= 0;` | Reservation released; pointer advances; available for arbitration next cycle. |
| **Case 4** | **Premature TAIL Accepted** | `output_locked=1`, `owner=i`, `type=TAIL`, `flit_count_next < decoded_len` | `out_valid && out_ready == 1` | `output_locked <= 0; locked_owner <= 0; priority_ptr <= (i+1)%5; ipc_state <= IPC_IDLE; status_framing_err <= 1;` | Lock released immediately to prevent output hanging; error latched. |
| **Case 5** | **Excess BODY Accepted** | `output_locked=1`, `owner=i`, `type=BODY`, `flit_count >= decoded_len` | `out_valid && out_ready == 1` | `output_locked <= 1; flit_count <= (flit_count==31)?31:flit_count+1; status_framing_err <= 1;` | Flit streamed forward; lock maintained; counter saturates at 31. |
| **Case 6** | **Excess TAIL Accepted** | `output_locked=1`, `owner=i`, `type=TAIL`, `flit_count_next > decoded_len` | `out_valid && out_ready == 1` | `output_locked <= 0; locked_owner <= 0; priority_ptr <= (i+1)%5; ipc_state <= IPC_IDLE; status_framing_err <= 1;` | Lock released immediately; excess framing error latched. |
| **Case 7** | **SINGLE Flit Accepted** | `output_locked=0`, `type=SINGLE` | `out_valid && out_ready == 1` | `output_locked <= 0; priority_ptr <= (i+1)%5; ipc_state <= IPC_IDLE; flit_count <= 0;` | Traverses in 1 cycle; pointer advances; no persistent lock acquired. |
| **Case 8** | **Output Backpressure** | `owner=i`, `out_ready=0` | `egress_handshake == 0` | All registers hold: `output_locked, locked_owner, flit_count, ipc_state` completely stable. | FIFO pop disabled; zero counter drift; path remains reserved. |
| **Case 9** | **FIFO Valid but Not Ready** | `fifo_valid=1`, `out_ready=0` | `egress_handshake == 0` | All registers hold stable. | No transfer occurs; zero state drift. |

> [!IMPORTANT]
> **No Premature Re-Grant Guarantee**: No egress port can be granted to another ingress port until the clock cycle *after* the previous packet's accepted `FLIT_TAIL` or `FLIT_SINGLE`. Mutual exclusion is absolute.

---

## 5. Rigorous Directed-Channel Dependency & Deadlock Proof

### 5.1 Directed Physical Channel Partitioning
In an $M \times N$ 2D mesh, every directed physical channel belongs to one of five disjoint classes:
1. **Eastbound Channels ($C_E$)**: $c_E(x, y)$ connecting $(x, y) \to (x+1, y)$ for $0 \le x < M-1, 0 \le y < N$.
2. **Westbound Channels ($C_W$)**: $c_W(x, y)$ connecting $(x, y) \to (x-1, y)$ for $1 \le x < M, 0 \le y < N$.
3. **Southbound Channels ($C_S$)**: $c_S(x, y)$ connecting $(x, y) \to (x, y+1)$ for $0 \le x < M, 0 \le y < N-1$.
4. **Northbound Channels ($C_N$)**: $c_N(x, y)$ connecting $(x, y) \to (x, y-1)$ for $0 \le x < M, 1 \le y < N$.
5. **Local Ejection Channels ($C_L$)**: $c_L(x, y)$ connecting router $(x, y)$ to its local sink endpoint.

### 5.2 Routing Turn Constraints Under Deterministic XY Routing
The combinational routing logic in `route_compute.sv` enforces the following strict rules:
- **Horizontal Progression**:
  - Eastbound packets only request Eastbound channels until $x = dest\_x$. ($E \to E$).
  - Westbound packets only request Westbound channels until $x = dest\_x$. ($W \to W$).
  - 180-degree turns ($E \to W$ and $W \to E$) are physically disabled.
- **Horizontal-to-Vertical Transitions**:
  - Once $x = dest\_x$, an Eastbound or Westbound packet can turn South ($E \to S, W \to S$), turn North ($E \to N, W \to N$), or eject Local ($E \to L, W \to L$).
- **Vertical Progression**:
  - Southbound packets only request Southbound channels ($S \to S$) or eject Local ($S \to L$).
  - Northbound packets only request Northbound channels ($N \to N$) or eject Local ($N \to L$).
- **Strictly Prohibited Turns**:
  - Vertical-to-Horizontal turns ($S \to E, S \to W, N \to E, N \to W$) are **physically impossible**.
  - Vertical-to-Vertical reversals ($S \to N, N \to S$) are **physically impossible**.

### 5.3 Formal Topological Ranking Function
We define a scalar ranking function $\mathcal{R}(c) \in \mathbb{N}$ over every individual directed channel:

$$\mathcal{R}(c_E(x, y)) = 1000 + x$$
$$\mathcal{R}(c_W(x, y)) = 1000 + (M - x)$$
$$\mathcal{R}(c_S(x, y)) = 2000 + y$$
$$\mathcal{R}(c_N(x, y)) = 2000 + (N - y)$$
$$\mathcal{R}(c_L(x, y)) = 3000$$

### 5.4 Proof that Every Permitted Dependency Strictly Increases Rank
Let $(c_a \to c_b)$ be any valid transition between consecutive channels along any path:
1. $c_E(x, y) \to c_E(x+1, y)$: $\mathcal{R}(c_a) = 1000 + x < 1000 + (x+1) = \mathcal{R}(c_b)$. (Strictly increases).
2. $c_W(x, y) \to c_W(x-1, y)$: $\mathcal{R}(c_a) = 1000 + (M - x) < 1000 + (M - (x-1)) = \mathcal{R}(c_b)$. (Strictly increases).
3. Horizontal to Vertical ($E \to S, E \to N, W \to S, W \to N$): $\mathcal{R}(c_a) \in [1000, 1000+M] < \mathcal{R}(c_b) \in [2000, 2000+N]$. (Strictly increases).
4. $c_S(x, y) \to c_S(x, y+1)$: $\mathcal{R}(c_a) = 2000 + y < 2000 + (y+1) = \mathcal{R}(c_b)$. (Strictly increases).
5. $c_N(x, y) \to c_N(x, y-1)$: $\mathcal{R}(c_a) = 2000 + (N - y) < 2000 + (N - (y-1)) = \mathcal{R}(c_b)$. (Strictly increases).
6. Any channel to Local ($E \to L, W \to L, S \to L, N \to L$): $\mathcal{R}(c_a) < 3000 = \mathcal{R}(c_b)$. (Strictly increases).

Since every permitted edge $(c_a \to c_b)$ in the Channel Dependency Graph satisfies $\mathcal{R}(c_a) < \mathcal{R}(c_b)$, **the complete directed Channel Dependency Graph is an Acyclic Directed Graph (DAG)**:
$$\text{Cycles}(CDG) = \emptyset$$

### 5.5 Extension to Wormhole Output Reservations
In wormhole switching, a packet holds a chain of output reservations:
$$\text{Held Locks}(P) = \{O(c_1), O(c_2), \dots, O(c_k)\}$$
Because every acquired lock $O(c)$ corresponds to a physical channel strictly ordered by $\mathcal{R}(c)$, the resource dependency graph of held and requested locks is isomorphic to a subgraph of the CDG.
By Dally and Seitz's Theorem (1987), an acyclic channel dependency graph guarantees that **circular wait cannot form**.

### 5.6 Architectural Rigor Statement & Environmental Assumptions
This is an architectural mathematical proof based on topological graph theory. It strictly assumes:
1. **Non-blocking sink consumption**: Destination endpoints must consume arriving flits from their Local egress port with bounded latency ($S_{\text{sink}} < \infty$).
2. **Finite packet lengths**: $L \le 16$.
3. **Sender tail completion**: Senders do not stall mid-packet indefinitely ($T_{\text{bubble}} < T_{\text{hang}}$).

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
