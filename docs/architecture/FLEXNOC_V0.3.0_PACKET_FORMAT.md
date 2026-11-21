# FlexNoC v0.3.0 — Multi-Flit Packet Format & Protocol Specification

- **Document Version**: 2.4 (Channel Dependency & Canonical Transfer Semantics Pass)
- **Status**: **APPROVED ARCHITECTURE SPECIFICATION**
- **Target Release**: FlexNoC v0.3.0
- **Authors**: FlexNoC Architecture, Verification, and Synthesis Teams
- **Associated Documents**:
  - [docs/architecture/FLEXNOC_V0.3.0_MULTI_FLIT_SPEC.md](FLEXNOC_V0.3.0_MULTI_FLIT_SPEC.md)
  - [docs/architecture/FLEXNOC_V0.3.0_ROUTER_STATE_MACHINE.md](FLEXNOC_V0.3.0_ROUTER_STATE_MACHINE.md)
  - [docs/architecture/FLEXNOC_V0.3.0_VERIFICATION_PLAN.md](FLEXNOC_V0.3.0_VERIFICATION_PLAN.md)
  - [docs/architecture/FLEXNOC_V0.3.0_DESIGN_REVIEW.md](FLEXNOC_V0.3.0_DESIGN_REVIEW.md)
  - [docs/architecture/FLEXNOC_V0.3.0_FINAL_CONSISTENCY_AUDIT.md](FLEXNOC_V0.3.0_FINAL_CONSISTENCY_AUDIT.md)

---

## 1. Architectural Scope & Objectives

This specification defines the packet formatting, framing semantics, bit-level field allocations, length encoding rules, canonical transfer event definitions, and handshake contracts for **multi-flit packet support** in FlexNoC v0.3.0.

### Primary Goals:
1. **Wormhole Multi-Flit Support**: Enable transmission of arbitrary-length data streams ($L \in [1, 16]$) across the NoC using structured **Header**, **Body**, and **Tail** flits.
2. **Bandwidth Optimization**: Eliminate redundant routing header overhead from Body and Tail flits, increasing payload capacity from 14 bits to **22 bits per flit (+57.1% payload efficiency)**.
3. **Canonical Egress Transfer Event**: Formally establish `egress_handshake = out_valid && out_ready` as the single authoritative event that advances packet counters and triggers reservation transitions.
4. **Rigorous Next-State Counter Sizing**: Provide an unambiguous 4-bit wire representation decoded into 5-bit hardware registers with explicit combinational next-state (`flit_count_next`) comparison semantics.
5. **Exhaustive Framing Encodings**: Formally establish that the 2-bit `flit_type` has four legal binary encodings with zero unmapped synthesizable codes, separating simulation-only X/Z detection.
6. **Bit-Level Compatibility Specification**: Detail exact bit mappings between baseline v0.1.0/v0.2.0 packets and v0.3.0 `FLIT_SINGLE`, specifying the required migration shim.
7. **Link-Level Robustness**: Maintain packet identity (`pkt_id`) across all flits for cycle-accurate scoreboarding, duplicate detection, and zero-tolerance interleaving verification.

---

## 2. Flit Types & Framing Enumeration

Each flit in FlexNoC v0.3.0 contains a mandatory 2-bit framing field (`flit_type`) occupying the most significant bit positions (`[31:30]` in a 32-bit flit):

```systemverilog
typedef enum logic [1:0] {
    FLIT_HEAD   = 2'b00, // Initiates multi-flit packet, sets destination, locks output reservation
    FLIT_BODY   = 2'b01, // Carries sequential payload along established reservation path
    FLIT_TAIL   = 2'b10, // Concludes packet, carries final payload, releases output reservation
    FLIT_SINGLE = 2'b11  // Atomically transmits 1-flit packet without persistent locking
} flit_type_e;
```

### 2.1 Complete Binary Encoding Space
The 2-bit `flit_type[1:0]` field maps to $2^2 = 4$ binary combinations. All four binary combinations are formally assigned:
- `2'b00`: `FLIT_HEAD` (Valid multi-flit header)
- `2'b01`: `FLIT_BODY` (Valid intermediate data flit)
- `2'b10`: `FLIT_TAIL` (Valid terminating flit)
- `2'b11`: `FLIT_SINGLE` (Valid single-flit autonomous transaction)

> [!NOTE]
> In synthesizable 2-state digital hardware, every 2-bit wire state resolves to one of the four legal protocol flit types. There are zero unassigned binary codes.
> 
> **Simulation-Only Metavalue Detection**: In 4-state simulation, uninitialized (`'x`) or high-impedance (`'z`) states represent design defects and are trapped via SystemVerilog Assertions (`$isunknown(flit_type)`). Synthesizable RTL includes a `default` case mapping unknown inputs safely to `IPC_ERROR` without generating latches.

### 2.2 Protocol Framing Grammar
A valid packet stream adheres strictly to the following formal grammar:
$$\text{Packet} ::= \text{FLIT\_SINGLE} \;\mid\; \text{FLIT\_HEAD} \cdot (\text{FLIT\_BODY})^* \cdot \text{FLIT\_TAIL}$$

---

## 3. Bit-Level Field Layouts

FlexNoC maintains a parameterizable `FLIT_WIDTH` with default $W = 32$ bits.

```
 31    30 29    28 27    26 25    24 23    22 21          14 13       10 9                         0
+--------+--------+--------+--------+--------+--------------+----------+-----------------------------+
| flit_ty| dest_x | dest_y | src_x  | src_y  |    pkt_id    | pkt_len  |        head_payload         |
| (2 b)  | (2 b)  | (2 b)  | (2 b)  | (2 b)  |    (8 b)     |  (4 b)   |           (10 b)            |
+--------+--------+--------+--------+--------+--------------+----------+-----------------------------+
  HEAD FLIT (flit_type = 2'b00)

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

---

## 4. Field Definitions & Semantics

### 4.1 Header Flit Fields (`FLIT_HEAD`, `2'b00`)
- **`flit_type` (`[31:30] = 2'b00`)**: Identifies multi-flit packet header. Triggers route computation and initiates atomic output reservation.
- **`dest_x` (`[29:28]`)**: Destination router mesh column coordinate ($0 \le X < \text{MESH\_WIDTH}$).
- **`dest_y` (`[27:26]`)**: Destination router mesh row coordinate ($0 \le Y < \text{MESH\_HEIGHT}$).
- **`src_x` (`[25:24]`)**: Source router column coordinate of originating endpoint.
- **`src_y` (`[23:22]`)**: Source router row coordinate of originating endpoint.
- **`pkt_id` (`[21:14]`)**: 8-bit transaction tag assigned by the source endpoint.
- **`pkt_len` (`[13:10]`)**: 4-bit encoded packet length ($L - 1$). See Section 5 for formal counter sizing.
- **`head_payload` (`[9:0]`)**: 10-bit initial payload (command opcode, address offset, or memory attributes).

### 4.2 Body Flit Fields (`FLIT_BODY`, `2'b01`)
- **`flit_type` (`[31:30] = 2'b01`)**: Identifies intermediate data flit.
- **`pkt_id` (`[29:22]`)**: Replicates the 8-bit transaction tag from `FLIT_HEAD`. Guarantees flit-level traceability and enables scoreboards to detect illegal interleaving.
- **`body_payload` (`[21:0]`)**: 22 bits of raw application data.

### 4.3 Tail Flit Fields (`FLIT_TAIL`, `2'b10`)
- **`flit_type` (`[31:30] = 2'b10`)**: Identifies the terminating flit. Triggers the sequential release of the output reservation lock and allows arbiter priority pointer advancement.
- **`pkt_id` (`[29:22]`)**: Transaction tag matching Header and Body flits.
- **`tail_payload` (`[21:0]`)**: 22 bits of final packet payload or transaction checksum.

### 4.4 Single-Flit Fields (`FLIT_SINGLE`, `2'b11`)
- **`flit_type` (`[31:30] = 2'b11`)**: Identifies an autonomous 1-flit transaction. Traverses crossbar in 1 cycle without locking.
- **`dest_x`, `dest_y`, `src_x`, `src_y` (`[29:22]`)**: Complete routing and return coordinates.
- **`pkt_id` (`[21:14]`)**: 8-bit transaction identifier.
- **`payload` (`[13:0]`)**: 14-bit data payload.

---

## 5. Packet Length Semantics & Canonical Handshake Events

### 5.1 Formal Definition of Length
- **Inclusion Scope**: `pkt_len` specifies the **total number of flits in the packet**, inclusive of `FLIT_HEAD`, all intermediate `FLIT_BODY` flits, and `FLIT_TAIL`.
- **Length Range**:
  - Minimum valid packet length: $L_{\min} = 1$ flit (for `FLIT_SINGLE`) or $L_{\min} = 2$ flits (for `FLIT_HEAD` + `FLIT_TAIL`).
  - Maximum valid packet length: $L_{\max} = 16$ flits (`FLIT_HEAD` + 14 `FLIT_BODY` + `FLIT_TAIL`).

### 5.2 4-Bit Wire Encoding to 5-Bit Hardware Registers
On the physical link, the length is encoded as:
$$\text{pkt\_len\_enc}[3:0] = 4'(L - 1)$$

Inside the router controller, network interface, and verification scoreboard, length is decoded into a 5-bit register:
$$\text{decoded\_len}[4:0] = \{1'\text{b0}, \text{pkt\_len\_enc}\} + 5'\text{d1}$$

### 5.3 Canonical Transfer Events & Sizing
FlexNoC strictly differentiates between ingress buffer enqueue and crossbar egress forwarding:
1. **FIFO Ingress Enqueue**: $\text{fifo\_enqueue}[i] = \text{in\_valid}[i] \land \text{in\_ready}[i]$. Pushes a flit into the FIFO. Does **not** advance the packet forwarding counter.
2. **Canonical Egress Transfer**: $\text{egress\_handshake}[o] = \text{out\_valid}[o] \land \text{out\_ready}[o]$. The authoritative event that advances `flit_count` and triggers reservation state transitions.

```systemverilog
always_comb begin
    flit_count_next[i] = flit_count[i];
    // Canonical condition: Flit is present at FIFO head, granted, and accepted at egress
    if (fifo_valid[i] && (arb_grant[active_out[i]][i] && out_ready[active_out[i]])) begin
        case (fifo_data[i][31:30])
            FLIT_HEAD:   flit_count_next[i] = 5'd1;
            FLIT_BODY:   flit_count_next[i] = (flit_count[i] == 5'd31) ? 5'd31 : (flit_count[i] + 5'd1);
            FLIT_TAIL:   flit_count_next[i] = (flit_count[i] == 5'd31) ? 5'd31 : (flit_count[i] + 5'd1);
            FLIT_SINGLE: flit_count_next[i] = 5'd1;
            default:     flit_count_next[i] = flit_count[i];
        endcase
    end
end
```

### 5.4 Same-Cycle Validation on Tail Flit Handshake
1. **Correct TAIL (`flit_count_next == decoded_len`)**: Clean completion; lock released, pointer advances, state returns to `IPC_IDLE`.
2. **Premature (Early) TAIL (`flit_count_next < decoded_len`)**: Lock released immediately (`output_locked <= 0`) to prevent port hanging; `status_framing_err` latched; scoreboard flags `ERR_PREMATURE_TAIL`.
3. **Excess Framing on TAIL (`flit_count_next > decoded_len`)**: Lock released immediately; `status_framing_err` latched; scoreboard flags `ERR_EXCESS_BODY`.
4. **Excess BODY Flits (`active_flit_type == FLIT_BODY` when `flit_count >= decoded_len`)**: Forwarded along locked crossbar; lock held; `flit_count_next` saturates at 31; `ERR_EXCESS_BODY` latched.
5. **TAIL Arrival After Saturation**: Lock released immediately on handshake; excess framing error latched.

---

## 6. Comprehensive Framing Anomaly Matrix (`ANOM-01` to `ANOM-09`)

Every protocol framing violation is assigned a permanent identifier (`ANOM-01` through `ANOM-09`) with explicit actions across both Ingress and Egress controllers:

| Anomaly ID | Condition Description | Detection Point | Forwarded? | Reservation Lock Action | Ingress Context Action | Status Signal | Recovery Mechanism | Verification Test ID |
| :---: | :--- | :--- | :---: | :---: | :--- | :--- | :--- | :---: |
| **ANOM-01** | **Early TAIL** (`flit_count_next < decoded_len` on `FLIT_TAIL`) | Receiver / Scoreboard upon `FLIT_TAIL` handshake | **Yes** (Tail forwarded) | **Released** immediately upon tail handshake | Transition to `IPC_IDLE`; clear latched route | `ERR_PREMATURE_TAIL` (sticky in monitor) | None in HW (lock freed naturally); SW marks packet corrupt | **TC-MF-11A, TC-MF-18** |
| **ANOM-02** | **Missing TAIL** (`flit_count >= decoded_len` and sender pauses without `TAIL`) | Monitor when count $\ge \text{decoded\_len}$ & link pauses | **N/A** (No flit arrives) | **Held** by active owner | Stays in `IPC_BODY` | `ERR_MISSING_TAIL`; `status_hang_alert` after $T_{\text{hang}}$ cycles | Coordinated Network Reset clears hung channel | **TC-MF-11B, TC-MF-19** |
| **ANOM-03** | **Excess BODY** (`FLIT_BODY` arrives when `flit_count >= decoded_len`) | IPC FSM & Monitor on each extra body flit | **Yes** (Streamed along path) | **Held** along path | `flit_count` increments up to 31; stays `IPC_BODY` | `ERR_EXCESS_BODY` (sticky in monitor) | Stream continues until `FLIT_TAIL` releases or watchdog resets | **TC-MF-11C, TC-MF-17** |
| **ANOM-04** | **Orphan BODY** (`FLIT_BODY` presented at ingress when in `IPC_IDLE`) | Ingress Port Controller (IPC) in `IPC_IDLE` | **No** (Transfer denied) | **No lock acquired** | Transitions to `IPC_ERROR`; FIFO pop disabled | `status_framing_err` (sticky in router) | Coordinated Network Reset or local exception clear | **TC-MF-11D** |
| **ANOM-05** | **Orphan TAIL** (`FLIT_TAIL` presented at ingress when in `IPC_IDLE`) | Ingress Port Controller (IPC) in `IPC_IDLE` | **No** (Transfer denied) | **No lock acquired** | Transitions to `IPC_ERROR`; FIFO pop disabled | `status_framing_err` (sticky in router) | Coordinated Network Reset or local exception clear | **TC-MF-11D** |
| **ANOM-06** | **Unexpected HEAD** (`FLIT_HEAD` arrives when in `IPC_BODY` or `IPC_TAIL`) | Ingress Port Controller (IPC) during active packet | **No** (Transfer blocked) | **Held** for original active packet | Latches framing error; transitions to `IPC_ERROR` | `status_framing_err` (sticky in router) | Channel hangs $\rightarrow$ Watchdog triggers Coordinated Reset | **TC-MF-11D** |
| **ANOM-07** | **Packet ID Mismatch** (`flit.pkt_id != latched_pkt_id` during body/tail) | Egress Monitor & IPC during streaming | **Yes** (Forwarded) | **Held** | Flagged in diagnostic status register | `status_pkt_id_mismatch` (sticky in monitor) | Scoreboard traps fatal interleaving; Coordinated Reset if stuck | **TC-MF-05** |
| **ANOM-08** | **Destination Out-of-Bounds** (`dest_x >= MESH_WIDTH` or `dest_y >= MESH_HEIGHT`) | Route Compute logic on `FLIT_HEAD` | **Diverted** to `PORT_LOCAL` | Reserved on `PORT_LOCAL` | Latches route to `PORT_LOCAL` with error flag | `route_err` (sticky in router) | Local core traps illegal address exception; drains packet | **TC-MF-11D** |
| **ANOM-09** | **Metastable / Unknown Flit Type** (`flit_type` contains `'x` or `'z` in simulation) | SVA assertion & `default` case in RTL | **No** (Blocked) | **No lock acquired** | Transitions to `IPC_ERROR` | SVA Fatal / `status_framing_err` | Simulation fatal failure; hardware default logic prevents latches | **TC-MF-11D** |

---

## 7. Backward Compatibility & Bit-Level Comparison

### 7.1 Baseline v0.1.0/v0.2.0 vs. v0.3.0 `FLIT_SINGLE`

| Bit Range | Baseline v0.1.0/v0.2.0 Field | Proposed v0.3.0 `FLIT_SINGLE` Field | Compatibility Analysis |
| :---: | :---: | :---: | :--- |
| `[31:30]` | `dest_x[1:0]` (2 b) | `flit_type[1:0] = 2'b11` (2 b) | **BREAKING**: Legacy `dest_x=2'b00` is decoded as `FLIT_HEAD` (`2'b00`)! |
| `[29:28]` | `dest_y[1:0]` (2 b) | `dest_x[1:0]` (2 b) | **BREAKING**: 2-bit rightward shift of destination X coordinate. |
| `[27:26]` | `src_x[1:0]` (2 b) | `dest_y[1:0]` (2 b) | **BREAKING**: Shifted coordinate field. |
| `[25:24]` | `src_y[1:0]` (2 b) | `src_x[1:0]` (2 b) | **BREAKING**: Shifted coordinate field. |
| `[23:22]` | `pkt_id[7:6]` (2 b) | `src_y[1:0]` (2 b) | **BREAKING**: Overlaps legacy packet ID bits. |
| `[21:14]` | `pkt_id[5:0]`, `payload[15:14]` | `pkt_id[7:0]` (8 b) | **BREAKING**: Aligned packet ID byte. |
| `[13:0]` | `payload[13:0]` (14 b) | `payload[13:0]` (14 b) | **Identical**: Lower 14 bits of payload preserved. |
| `[15:14]` | `payload[15:14]` (2 b) | *Absorbed into framing/pkt_id* | Single flit payload reduced from 16b to 14b. |

### 7.2 Compatibility Shim Architecture (`flexnoc_v1_adapter`)
To support legacy endpoints without modifying their interface, FlexNoC specifies an optional conversion shim:

```systemverilog
module flexnoc_v1_adapter (
    input  logic [31:0] v1_data,
    input  logic        v1_valid,
    output logic        v1_ready,
    output logic [31:0] v3_data,
    output logic        v3_valid,
    input  logic        v3_ready
);
    // Transcode v0.1.0 single-flit format into v0.3.0 FLIT_SINGLE
    assign v3_valid = v1_valid;
    assign v1_ready = v3_ready;
    assign v3_data  = {
        2'b11,             // [31:30] FLIT_SINGLE framing
        v1_data[31:30],    // [29:28] dest_x
        v1_data[29:28],    // [27:26] dest_y
        v1_data[27:26],    // [25:24] src_x
        v1_data[25:24],    // [23:22] src_y
        v1_data[23:16],    // [21:14] pkt_id
        v1_data[13:0]      // [13:0]  payload (truncated to 14 bits)
    };
endmodule
```

---

## 8. Flow Control & Handshake Semantics

The canonical ready/valid handshake is enforced across all flit types:
$$\text{Transfer Occurs} \iff \text{egress\_handshake}[o] = \text{out\_valid}[o] \land \text{out\_ready}[o] \land \text{posedge(clk)}$$

### Multi-Flit Invariants:
1. **Flit Atomicity**: Each flit transfer is atomic.
2. **Stall Stability**: When `valid` is HIGH and `ready` is LOW, data remains stable and cannot be replaced.
3. **Zero Interleaving on Link**: Once `FLIT_HEAD` is accepted on an output port, all subsequent transfers on that port must belong strictly to the same packet until `FLIT_TAIL` handshakes.
