// ==============================================================================
// File: tb_mesh_performance.sv
// Project: FlexNoC - Configurable Network-on-Chip
// Description: Cycle-accurate performance benchmark harness for FlexNoC 4x4 mesh.
//              Supports Uniform Random, Hotspot, Neighbor, and Burst traffic patterns.
//              Measures packet latency, p95/p99 tail latency, throughput, and
//              saturation across offered load sweeps.
// ==============================================================================

`timescale 1ns/1ps

module tb_mesh_performance;

    import flexnoc_pkg::*;

    localparam int unsigned DATA_WIDTH  = 32;
    localparam int unsigned X_WIDTH     = 2;
    localparam int unsigned Y_WIDTH     = 2;
    localparam int unsigned FIFO_DEPTH  = 4;
    localparam int unsigned MESH_WIDTH  = 4;
    localparam int unsigned MESH_HEIGHT = 4;
    localparam int unsigned NUM_NODES   = MESH_WIDTH * MESH_HEIGHT; // 16 nodes
    localparam int unsigned MAX_SAMPLES = 5000;

    logic clk;
    logic rst_n;

    // Local interfaces
    logic [(NUM_NODES*DATA_WIDTH)-1:0] in_local_data;
    logic [NUM_NODES-1:0]              in_local_valid;
    wire  [NUM_NODES-1:0]              in_local_ready;

    wire  [(NUM_NODES*DATA_WIDTH)-1:0] out_local_data;
    wire  [NUM_NODES-1:0]              out_local_valid;
    logic [NUM_NODES-1:0]              out_local_ready;

    wire  [NUM_NODES-1:0]              status_err;

    // Simulation control parameters (configurable via plusargs)
    int traffic_pattern = 0; // 0: Uniform, 1: Hotspot, 2: Neighbor, 3: Burst
    int offered_rate    = 20; // Offered load percentage (1 to 100%)
    int target_packets  = 500;
    int rand_seed       = 42;

    // Performance Counters
    int unsigned current_cycle = 0;
    int unsigned start_cycle   = 0;
    int unsigned end_cycle     = 0;
    int unsigned total_injected = 0;
    int unsigned total_delivered = 0;

    int latency_samples [MAX_SAMPLES];
    int sample_count = 0;
    longint total_latency = 0;
    int min_latency = 999999;
    int max_latency = 0;

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Cycle counter
    always @(posedge clk) begin
        if (rst_n) current_cycle++;
    end

    // DUT: 4x4 Mesh
    mesh_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .X_WIDTH    (X_WIDTH),
        .Y_WIDTH    (Y_WIDTH),
        .FIFO_DEPTH (FIFO_DEPTH),
        .MESH_WIDTH (MESH_WIDTH),
        .MESH_HEIGHT(MESH_HEIGHT)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .in_local_data  (in_local_data),
        .in_local_valid (in_local_valid),
        .in_local_ready (in_local_ready),
        .out_local_data (out_local_data),
        .out_local_valid(out_local_valid),
        .out_local_ready(out_local_ready),
        .status_err     (status_err)
    );

    // --------------------------------------------------------------------------
    // Autonomous Ejection Monitor & Cycle-Accurate Latency Collector
    // --------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            for (int n = 0; n < int'(NUM_NODES); n++) begin
                if (out_local_valid[n] && out_local_ready[n]) begin
                    logic [DATA_WIDTH-1:0] flit;
                    int inject_time;
                    int lat;

                    flit = out_local_data[(n*DATA_WIDTH) +: DATA_WIDTH];
                    inject_time = int'(get_payload(flit));
                    lat = int'(current_cycle) - inject_time;

                    total_delivered++;
                    total_latency += lat;
                    if (lat < min_latency) min_latency = lat;
                    if (lat > max_latency) max_latency = lat;

                    if (sample_count < int'(MAX_SAMPLES)) begin
                        latency_samples[sample_count] = lat;
                        sample_count++;
                    end
                end
            end
        end
    end

    // Destination selection according to traffic pattern
    function automatic int get_destination(int src);
        int dst;
        case (traffic_pattern)
            0: begin // Uniform Random
                do begin
                    dst = $urandom_range(0, NUM_NODES-1);
                end while (dst == src);
            end
            1: begin // Hotspot (30% to Node 0, remainder uniform)
                if ($urandom_range(0, 99) < 30) begin
                    dst = 0;
                end else begin
                    do begin
                        dst = $urandom_range(0, NUM_NODES-1);
                    end while (dst == src);
                end
            end
            2: begin // Neighbor Traffic
                int sx, sy, dir;
                sx = src % MESH_WIDTH;
                sy = src / MESH_WIDTH;
                dir = $urandom_range(0, 3);
                case (dir)
                    0: dst = (sx < MESH_WIDTH-1) ? src + 1 : src - 1; // East / West
                    1: dst = (sx > 0) ? src - 1 : src + 1;
                    2: dst = (sy < MESH_HEIGHT-1) ? src + MESH_WIDTH : src - MESH_WIDTH; // South / North
                    3: dst = (sy > 0) ? src - MESH_WIDTH : src + MESH_WIDTH;
                endcase
            end
            default: begin
                dst = (src + 1) % NUM_NODES;
            end
        endcase
        return dst;
    endfunction

    // --------------------------------------------------------------------------
    // Main Benchmark Execution Process
    // --------------------------------------------------------------------------
    initial begin
        // Read plusargs
        void'($value$plusargs("TRAFFIC=%d", traffic_pattern));
        void'($value$plusargs("RATE=%d", offered_rate));
        void'($value$plusargs("PACKETS=%d", target_packets));
        void'($value$plusargs("SEED=%d", rand_seed));

        void'($urandom(rand_seed));

        $display("==================================================");
        $display(" FlexNoC Benchmark: 4x4 Mesh Performance Sweep");
        $display(" Pattern=%0d (0:Uniform, 1:Hotspot, 2:Neighbor)", traffic_pattern);
        $display(" Offered Rate=%0d%%, Target Packets=%0d, Seed=%0d", offered_rate, target_packets, rand_seed);
        $display("==================================================");

        rst_n           = 0;
        in_local_data   = '0;
        in_local_valid  = '0;
        out_local_ready = {NUM_NODES{1'b1}};

        repeat (10) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        @(posedge clk);
        start_cycle = current_cycle;

        // Injection Loop
        while (total_injected < int'(target_packets)) begin
            @(negedge clk);
            for (int n = 0; n < int'(NUM_NODES); n++) begin
                if (total_injected < int'(target_packets)) begin
                    // Bernoulli injection trial based on offered_rate
                    if ($urandom_range(0, 99) < offered_rate && in_local_ready[n]) begin
                        int dst;
                        int dx, dy, sx, sy;
                        logic [DATA_WIDTH-1:0] flit;

                        dst = get_destination(n);
                        sx = n % MESH_WIDTH;
                        sy = n / MESH_WIDTH;
                        dx = dst % MESH_WIDTH;
                        dy = dst / MESH_WIDTH;

                        // Embed current_cycle into payload for cycle-accurate latency
                        flit = create_flit(X_WIDTH'(dx), Y_WIDTH'(dy), X_WIDTH'(sx), Y_WIDTH'(sy), 
                                           8'(total_injected & 8'hFF), 16'(current_cycle & 16'hFFFF));

                        in_local_data[(n*DATA_WIDTH) +: DATA_WIDTH] = flit;
                        in_local_valid[n] = 1'b1;
                        total_injected++;
                    end else begin
                        in_local_valid[n] = 1'b0;
                    end
                end else begin
                    in_local_valid[n] = 1'b0;
                end
            end
            @(posedge clk);
        end

        // Cease injection
        @(negedge clk);
        in_local_valid = '0;

        // Drain Phase: wait until all injected packets are delivered (or timeout)
        begin
            int drain_timeout;
            drain_timeout = 2000;
            while ((total_delivered < total_injected) && (drain_timeout > 0)) begin
                @(posedge clk);
                drain_timeout--;
            end
        end

        end_cycle = current_cycle;

        // ----------------------------------------------------------------------
        // Statistical Analysis & Report
        // ----------------------------------------------------------------------
        begin
            real avg_lat;
            real throughput;
            int p50, p95, p99;
            int total_sim_cycles;
            int temp;

            total_sim_cycles = int'(end_cycle - start_cycle);
            avg_lat    = (sample_count > 0) ? (real'(total_latency) / real'(sample_count)) : 0.0;
            throughput = (total_sim_cycles > 0) ? (real'(total_delivered) / real'(total_sim_cycles)) : 0.0;

            // Sort sample array for percentiles (bubble sort on collected samples)
            for (int i = 0; i < sample_count-1; i++) begin
                for (int j = 0; j < sample_count-i-1; j++) begin
                    if (latency_samples[j] > latency_samples[j+1]) begin
                        temp = latency_samples[j];
                        latency_samples[j] = latency_samples[j+1];
                        latency_samples[j+1] = temp;
                    end
                end
            end

            p50 = (sample_count > 0) ? latency_samples[int'(sample_count * 0.50)] : 0;
            p95 = (sample_count > 0) ? latency_samples[int'(sample_count * 0.95)] : 0;
            p99 = (sample_count > 0) ? latency_samples[int'(sample_count * 0.99)] : 0;

            $display("--------------------------------------------------");
            $display(" BENCHMARK RESULTS SUMMARY");
            $display("--------------------------------------------------");
            $display(" Total Injected       : %0d flits", total_injected);
            $display(" Total Delivered      : %0d flits", total_delivered);
            $display(" Total Simulation Time: %0d cycles", total_sim_cycles);
            $display(" Aggregate Throughput : %0.4f flits/cycle", throughput);
            $display(" Min Latency          : %0d cycles", min_latency);
            $display(" Avg Latency          : %0.2f cycles", avg_lat);
            $display(" Median (p50) Latency : %0d cycles", p50);
            $display(" 95th-Percentile (p95): %0d cycles", p95);
            $display(" 99th-Percentile (p99): %0d cycles", p99);
            $display(" Max Latency          : %0d cycles", max_latency);
            $display(" Packet Loss Rate     : %0.2f%%", 
                     100.0 * (1.0 - (real'(total_delivered)/real'(total_injected))));
            $display("--------------------------------------------------");

            // Write machine-readable JSON metrics to file
            begin
                int fd;
                fd = $fopen("results/benchmark_summary.json", "w");
                if (fd) begin
                    $fdisplay(fd, "{");
                    $fdisplay(fd, "  \"traffic_pattern\": %0d,", traffic_pattern);
                    $fdisplay(fd, "  \"offered_rate\": %0d,", offered_rate);
                    $fdisplay(fd, "  \"injected\": %0d,", total_injected);
                    $fdisplay(fd, "  \"delivered\": %0d,", total_delivered);
                    $fdisplay(fd, "  \"total_cycles\": %0d,", total_sim_cycles);
                    $fdisplay(fd, "  \"throughput\": %0.4f,", throughput);
                    $fdisplay(fd, "  \"min_latency\": %0d,", min_latency);
                    $fdisplay(fd, "  \"avg_latency\": %0.2f,", avg_lat);
                    $fdisplay(fd, "  \"p50_latency\": %0d,", p50);
                    $fdisplay(fd, "  \"p95_latency\": %0d,", p95);
                    $fdisplay(fd, "  \"p99_latency\": %0d,", p99);
                    $fdisplay(fd, "  \"max_latency\": %0d", max_latency);
                    $fdisplay(fd, "}");
                    $fclose(fd);
                    $display("[INFO] Exported benchmark metrics to results/benchmark_summary.json");
                end
            end

            if (total_delivered == total_injected) begin
                $display("[ALL BENCHMARK PACKETS DELIVERED SUCCESSFULLY]");
                $finish(0);
            end else begin
                $display("[ERROR: INCOMPLETE DRAIN OR PACKET LOSS DETECTED]");
                $finish(1);
            end
        end
    end

endmodule
