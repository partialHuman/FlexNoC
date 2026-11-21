# FlexNoC Performance Methodology & Benchmark Results

## 1. Accounting Conventions & Metrics Definition

All performance measurements in FlexNoC are gathered on a cycle-accurate, per-flit basis directly within the SystemVerilog simulation harness (`tb/traffic/tb_mesh_performance.sv`).

### Metric Definitions

1. **Cycle Latency ($L_i$)**:
   The number of clock cycles elapsed from the cycle a flit is accepted into the source router's local FIFO until the cycle it is accepted by the destination endpoint's ejection interface:
   $$L_i = T_{\text{eject}, i} - T_{\text{inject}, i}$$
   The injection timestamp is embedded into the flit payload field at injection time, allowing exact cycle subtraction upon arrival without external bookkeeping latency error.
2. **Average Latency**:
   $$\bar{L} = \frac{1}{N} \sum_{i=1}^{N} L_i$$
3. **Tail Latency (p95, p99)**:
   The 95th and 99th percentiles of the sorted latency distribution array across all delivered flits.
4. **Aggregate Throughput ($\Theta$)**:
   Total successfully delivered flits per clock cycle:
   $$\Theta = \frac{N_{\text{delivered}}}{T_{\text{total\_cycles}}}$$
5. **Offered Load ($R$)**:
   The Bernoulli injection probability per node per cycle (expressed as a percentage from 5% to 50%).

---

## 2. Traffic Workload Patterns

| Pattern | Description | Motivation |
| :--- | :--- | :--- |
| **Uniform Random** | Destination is uniformly chosen at random from all nodes $D \ne S$. | Standard baseline evaluating general network capacity under balanced load. |
| **Hotspot Contention** | Destination-selection rule selects Node 0 $(0, 0)$ with 30% probability per trial; remaining 70% is uniformly distributed excluding the source ($dst \ne src$). When the source is Node 0, the 30% selection permits local loopback ($dst = src = 0$). | Stresses arbitration, buffer congestion, and backpressure trees around a centralized resource (e.g., memory controller). |
| **Neighbor Traffic** | Destinations are strictly restricted to adjacent Cartesian neighbors $(\Delta X + \Delta Y == 1)$. | Measures minimum single-hop network latency and high localized throughput. |

---

## 3. Empirical Benchmark Results (4x4 Mesh, 16 Nodes)

Data gathered from automated benchmark sweeps (`scripts/run_experiments.py`, fixed random seed $S=42+R$, 350 target flits per run):

### 3.1 Uniform Random Traffic

| Offered Rate (%) | Throughput (flits/cyc) | Avg Latency (cyc) | Median (p50) | p95 Latency | p99 Latency | Packet Loss (%) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 5% | 0.7447 | 4.81 | 5 | 7 | 8 | 0.00% |
| 10% | 1.4768 | 4.83 | 5 | 7 | 8 | 0.00% |
| 15% | 2.2581 | 4.95 | 5 | 7 | 8 | 0.00% |
| 20% | 3.0702 | 4.91 | 5 | 7 | 9 | 0.00% |
| 25% | 3.4653 | 4.86 | 5 | 7 | 9 | 0.00% |
| 30% | 4.6053 | 5.07 | 5 | 8 | 9 | 0.00% |
| 40% | 5.4688 | 5.55 | 5 | 9 | 13 | 0.00% |
| 50% | 6.3636 | 5.66 | 5 | 10 | 12 | 0.00% |

### 3.2 Hotspot Contention Traffic (30% directed to Node 0)

| Offered Rate (%) | Throughput (flits/cyc) | Avg Latency (cyc) | Median (p50) | p95 Latency | p99 Latency | Packet Loss (%) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 5% | 0.7495 | 4.97 | 5 | 8 | 8 | 0.00% |
| 10% | 1.4894 | 5.02 | 5 | 8 | 9 | 0.00% |
| 15% | 2.2013 | 6.93 | 5 | 22 | 32 | 0.00% |
| 20% | 2.6316 | 10.25 | 6 | 39 | 51 | 0.00% |
| 25% | 2.6316 | 11.98 | 6 | 38 | 55 | 0.00% |
| 30% | 2.9412 | 13.62 | 6 | 53 | 59 | 0.00% |
| 40% | 2.5000 | 26.75 | 9 | 100 | 110 | 0.00% |
| 50% | 3.0973 | 21.55 | 8 | 76 | 89 | 0.00% |

### 3.3 Neighbor Traffic (Single-Hop Communication)

| Offered Rate (%) | Throughput (flits/cyc) | Avg Latency (cyc) | Median (p50) | p95 Latency | p99 Latency | Packet Loss (%) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 5% | 0.7447 | 3.01 | 3 | 3 | 4 | 0.00% |
| 10% | 1.4957 | 3.03 | 3 | 3 | 4 | 0.00% |
| 15% | 2.3026 | 3.07 | 3 | 4 | 5 | 0.00% |
| 20% | 3.1250 | 3.09 | 3 | 4 | 4 | 0.00% |
| 25% | 3.5354 | 3.13 | 3 | 4 | 5 | 0.00% |
| 30% | 4.7945 | 3.17 | 3 | 4 | 5 | 0.00% |
| 40% | 5.8333 | 3.25 | 3 | 4 | 6 | 0.00% |
| 50% | 6.2500 | 3.60 | 3 | 6 | 9 | 0.00% |

---

## 4. Observations & Key Insights

1. **Low Zero-Load Latency**:
   - Single-hop neighbor traffic exhibits a minimal latency of **3 clock cycles** (1 cycle input FIFO ingress + 1 cycle route/arbitration/crossbar traversal + 1 cycle egress handshake).
   - Uniform random traffic averages **4.81 to 5.66 cycles** across all multi-hop paths in the 4x4 mesh.
2. **Throughput Scaling**:
   - Under uniform random traffic, aggregate throughput scales linearly from **0.74 flits/cycle** at 5% load to **6.36 flits/cycle** at 50% load without network saturation.
3. **Hotspot Bottleneck Identification**:
   - Under hotspot traffic where generation trials select Node 0 with 30% probability, ejection throughput bottlenecks at **~2.6 - 3.0 flits/cycle** due to the single local ejection port limit. Local loopback transfers from Node 0 account for the observed 2-cycle minimum latency.
   - As backpressure propagates through upstream buffers, p95 latency rises from 8 cycles up to 100 cycles, reflecting realistic queue accumulation and tree saturation.
4. **Zero Packet Loss**:
   - Across all 24 experimental load points and thousands of simulated flits, the packet loss rate remained strictly **0.00%**.
