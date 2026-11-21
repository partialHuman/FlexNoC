# FlexNoC Known Limitations & Technical Assumptions

## 1. Scope & Implementation Boundaries

FlexNoC is currently at **v0.2.0 (Stable Baseline)**. To preserve engineering integrity and prevent misrepresentation, all operational limitations and boundary conditions are explicitly documented below.

| Feature Area | Current Baseline Implementation | Planned Extension / Deferred |
| :--- | :--- | :--- |
| **Topology** | 2D Mesh ($2\times2$ and $4\times4$ verified) | Torus, Ring, Hexagonal Mesh |
| **Routing Algorithm** | Deterministic Dimension-Order XY | Adaptive routing, West-first, DyXY |
| **Packet Structure** | Fixed-width single-flit packet (32 bits default) | Multi-flit packets (Head/Body/Tail framing, planned v0.3.0) |
| **Virtual Channels** | Single physical channel per port (no VCs) | Multi-VC buffering with VC allocators |
| **Flow Control** | Credit-less Ready/Valid Handshake | Credit-based flow control |
| **Clocking** | Synchronous single-clock network | Multi-clock asynchronous boundary FIFOs |
| **Deadlock Freedom** | Guaranteed by XY turn prohibition + liveness assumption | CDG formal verification |
| **Physical Design** | Generic Yosys synthesis | OpenROAD ASIC tapeout / FPGA bitstream |

---

## 2. Technical Assumptions & Operating Conditions

1. **Endpoint Liveness Assumption**:
   - The mathematical guarantee of deadlock freedom in dimension-order XY routing assumes that destination endpoints eventually assert `out_local_ready = 1` and consume arriving flits.
   - If an endpoint permanently halts consumption (`out_local_ready = 0` indefinitely), backpressure will fill input FIFOs backwards through the network tree and stall dependent upstream channels.
2. **Deterministic Single-Flit Ordering**:
   - Because single-flit packets follow deterministic XY paths, flits transmitted from source $A$ to destination $B$ arrive in strict FIFO order.
   - No ordering guarantees are provided across distinct source-destination streams.
3. **Boundary Condition Constraints**:
   - Packets addressing coordinates beyond the configured mesh dimensions ($\text{dest\_x} \ge \text{MESH\_WIDTH}$ or $\text{dest\_y} \ge \text{MESH\_HEIGHT}$) trigger `route_err` and are diverted to the local port for exception handling rather than traversing boundary links.
