// ==============================================================================
// File: tb_mesh_2x2.sv
// Project: FlexNoC - Configurable Network-on-Chip
// Description: Comprehensive verification testbench for 2x2 mesh_top.
//              Tests all 12 directed inter-node pairs, 4 local loopbacks,
//              multi-hop routing, backpressure, and concurrent multi-node injection
//              using autonomous per-node receiver monitors and scoreboarding.
// ==============================================================================

`timescale 1ns/1ps

module tb_mesh_2x2;

    import flexnoc_pkg::*;

    localparam int unsigned DATA_WIDTH  = 32;
    localparam int unsigned X_WIDTH     = 2;
    localparam int unsigned Y_WIDTH     = 2;
    localparam int unsigned FIFO_DEPTH  = 4;
    localparam int unsigned MESH_WIDTH  = 2;
    localparam int unsigned MESH_HEIGHT = 2;
    localparam int unsigned NUM_NODES   = MESH_WIDTH * MESH_HEIGHT; // 4 nodes

    logic clk;
    logic rst_n;

    // Flattened Endpoint local interfaces
    logic [(NUM_NODES*DATA_WIDTH)-1:0] in_local_data;
    logic [NUM_NODES-1:0]              in_local_valid;
    wire  [NUM_NODES-1:0]              in_local_ready;

    wire  [(NUM_NODES*DATA_WIDTH)-1:0] out_local_data;
    wire  [NUM_NODES-1:0]              out_local_valid;
    logic [NUM_NODES-1:0]              out_local_ready;

    wire  [NUM_NODES-1:0]              status_err;

    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    int packets_injected = 0;
    int packets_delivered = 0;

    // Per-node received flit queues
    logic [DATA_WIDTH-1:0] rx_q0 [$];
    logic [DATA_WIDTH-1:0] rx_q1 [$];
    logic [DATA_WIDTH-1:0] rx_q2 [$];
    logic [DATA_WIDTH-1:0] rx_q3 [$];

    // Clock generator (100 MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT
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
    // Autonomous Receiver Monitors (1 per node)
    // --------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            if (out_local_valid[0] && out_local_ready[0]) begin
                rx_q0.push_back(out_local_data[(0*DATA_WIDTH) +: DATA_WIDTH]);
                packets_delivered++;
            end
            if (out_local_valid[1] && out_local_ready[1]) begin
                rx_q1.push_back(out_local_data[(1*DATA_WIDTH) +: DATA_WIDTH]);
                packets_delivered++;
            end
            if (out_local_valid[2] && out_local_ready[2]) begin
                rx_q2.push_back(out_local_data[(2*DATA_WIDTH) +: DATA_WIDTH]);
                packets_delivered++;
            end
            if (out_local_valid[3] && out_local_ready[3]) begin
                rx_q3.push_back(out_local_data[(3*DATA_WIDTH) +: DATA_WIDTH]);
                packets_delivered++;
            end
        end
    end

    task check(input string test_name, input bit condition);
        test_count++;
        if (condition) begin
            pass_count++;
        end else begin
            fail_count++;
            $display("[FAIL] %s", test_name);
        end
    endtask

    function automatic int get_node_x(int id);
        return id % MESH_WIDTH;
    endfunction

    function automatic int get_node_y(int id);
        return id / MESH_WIDTH;
    endfunction

    // Clear all injection inputs
    task clear_injections();
        in_local_data  = '0;
        in_local_valid = '0;
    endtask

    // Inject a packet into source node
    task inject_packet(
        input int src_node,
        input int dest_node,
        input logic [7:0] pkt_id,
        input logic [15:0] payload
    );
        int sx, sy, dx, dy;
        logic [DATA_WIDTH-1:0] flit;

        sx = get_node_x(src_node);
        sy = get_node_y(src_node);
        dx = get_node_x(dest_node);
        dy = get_node_y(dest_node);

        flit = create_flit(X_WIDTH'(dx), Y_WIDTH'(dy), X_WIDTH'(sx), Y_WIDTH'(sy), pkt_id, payload);

        @(negedge clk);
        while (!in_local_ready[src_node]) begin
            @(posedge clk);
            @(negedge clk);
        end

        in_local_data[(src_node*DATA_WIDTH) +: DATA_WIDTH] = flit;
        in_local_valid[src_node] = 1'b1;
        packets_injected++;

        @(posedge clk);
        @(negedge clk);
        in_local_valid[src_node] = 1'b0;
    endtask

    // Pop and verify packet from destination queue with timeout
    task verify_received_packet(
        input int dest_node,
        input int expected_src,
        input logic [7:0] expected_pkt_id,
        input logic [15:0] expected_payload,
        input string desc
    );
        int timeout;
        logic [DATA_WIDTH-1:0] flit;
        bit found;

        timeout = 50;
        found = 0;

        while (timeout > 0 && !found) begin
            case (dest_node)
                0: if (rx_q0.size() > 0) begin flit = rx_q0.pop_front(); found = 1; end
                1: if (rx_q1.size() > 0) begin flit = rx_q1.pop_front(); found = 1; end
                2: if (rx_q2.size() > 0) begin flit = rx_q2.pop_front(); found = 1; end
                3: if (rx_q3.size() > 0) begin flit = rx_q3.pop_front(); found = 1; end
            endcase
            if (!found) @(posedge clk);
            timeout--;
        end

        if (found) begin
            check($sformatf("%s: payload match", desc), get_payload(flit) === expected_payload);
            check($sformatf("%s: pkt_id match", desc), flit[23:16] === expected_pkt_id);
            check($sformatf("%s: src_x match", desc), flit[27:26] === X_WIDTH'(get_node_x(expected_src)));
            check($sformatf("%s: src_y match", desc), flit[25:24] === Y_WIDTH'(get_node_y(expected_src)));
            check($sformatf("%s: dest_x match", desc), flit[31:30] === X_WIDTH'(get_node_x(dest_node)));
            check($sformatf("%s: dest_y match", desc), flit[29:28] === Y_WIDTH'(get_node_y(dest_node)));
        end else begin
            $display("[FAIL] %s: TIMEOUT waiting for flit at Node %0d", desc, dest_node);
            check($sformatf("%s: Received before timeout", desc), 1'b0);
        end
    endtask

    initial begin
        $display("==================================================");
        $display(" Starting 2x2 Mesh Integration Tests: tb_mesh_2x2");
        $display("==================================================");

        rst_n           = 0;
        clear_injections();
        out_local_ready = {NUM_NODES{1'b1}};

        // Reset
        repeat (5) @(posedge clk);
        check("Test 1: Zero error flags after reset", status_err === {NUM_NODES{1'b0}});
        check("Test 1: All out_valid low after reset", out_local_valid === {NUM_NODES{1'b0}});

        @(negedge clk);
        rst_n = 1;
        @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 2: All 12 Directed Inter-Node Pairs Sweep
        // Node 0: (0,0), Node 1: (1,0), Node 2: (0,1), Node 3: (1,1)
        // ----------------------------------------------------------------------
        $display("--- Testing All 12 Directed Node-to-Node Flows ---");
        for (int src = 0; src < NUM_NODES; src++) begin
            for (int dst = 0; dst < NUM_NODES; dst++) begin
                if (src != dst) begin
                    logic [7:0] pid;
                    logic [15:0] pld;
                    pid = 8'h10 + 8'(src*4 + dst);
                    pld = 16'h5000 + 16'(src*16 + dst);

                    inject_packet(src, dst, pid, pld);
                    verify_received_packet(dst, src, pid, pld, $sformatf("Pair (%0d->%0d)", src, dst));
                end
            end
        end

        // ----------------------------------------------------------------------
        // Test 3: Local Loopback at All 4 Nodes
        // ----------------------------------------------------------------------
        $display("--- Testing Local Loopback on All 4 Nodes ---");
        for (int node = 0; node < NUM_NODES; node++) begin
            logic [7:0] pid;
            logic [15:0] pld;
            pid = 8'h80 + 8'(node);
            pld = 16'hA000 + 16'(node);

            inject_packet(node, node, pid, pld);
            verify_received_packet(node, node, pid, pld, $sformatf("Local loopback Node %0d", node));
        end

        // ----------------------------------------------------------------------
        // Test 4: Downstream Backpressure Multi-Hop Propagation
        // Node 0 sends to Node 3 (2 hops).
        // Node 3 asserts out_local_ready = 0 for 5 cycles.
        // ----------------------------------------------------------------------
        $display("--- Testing Multi-Hop Backpressure Stall ---");
        @(negedge clk);
        out_local_ready[3] = 0; // Stall Node 3 local ejection

        inject_packet(0, 3, 8'hFE, 16'hBEAF);

        // Wait 4 cycles for flit to reach Node 3's output
        repeat (4) @(posedge clk);
        #1;
        check("Test 4a: Flit arrived at Node 3 local egress while stalled", out_local_valid[3] === 1'b1);

        // Verify flit remains completely stable during stall
        for (int s = 0; s < 5; s++) begin
            @(posedge clk);
            #1;
            check($sformatf("Test 4_stall[%0d]: Valid stable", s), out_local_valid[3] === 1'b1);
        end

        // Release stall
        @(negedge clk);
        out_local_ready[3] = 1;
        verify_received_packet(3, 0, 8'hFE, 16'hBEAF, "Stalled flit delivery at Node 3");

        // ----------------------------------------------------------------------
        // Test 5: Concurrent Multi-Node Injection
        // Node 0 -> Node 3, Node 1 -> Node 2 simultaneously!
        // ----------------------------------------------------------------------
        $display("--- Testing Concurrent Multi-Node Injection ---");
        @(negedge clk);
        in_local_data[(0*DATA_WIDTH) +: DATA_WIDTH] = create_flit(1, 1, 0, 0, 8'hD0, 16'hD001);
        in_local_valid[0] = 1'b1;
        in_local_data[(1*DATA_WIDTH) +: DATA_WIDTH] = create_flit(0, 1, 1, 0, 8'hD1, 16'hD002);
        in_local_valid[1] = 1'b1;
        packets_injected += 2;
        @(posedge clk);
        @(negedge clk);
        clear_injections();

        // Both flits must arrive at Node 3 and Node 2
        verify_received_packet(3, 0, 8'hD0, 16'hD001, "Concurrent Node 0->3");
        verify_received_packet(2, 1, 8'hD1, 16'hD002, "Concurrent Node 1->2");

        // ----------------------------------------------------------------------
        // Final Scoreboard Verification
        // ----------------------------------------------------------------------
        repeat (5) @(posedge clk);
        #1;
        $display("Final Packet Accounting: Injected=%0d, Delivered=%0d", 
                 packets_injected, packets_delivered);
        check("Scoreboard: 100% of injected packets successfully delivered", 
              packets_injected == packets_delivered);
        check("Final: No undelivered packets pending", out_local_valid === {NUM_NODES{1'b0}});
        check("Final: Zero mesh error flags", status_err === {NUM_NODES{1'b0}});

        // ----------------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------------
        $display("==================================================");
        $display(" tb_mesh_2x2 Complete: Total=%0d, Pass=%0d, Fail=%0d",
                 test_count, pass_count, fail_count);
        $display("==================================================");

        if (fail_count == 0) begin
            $display("[ALL TESTS PASSED]");
            $finish(0);
        end else begin
            $display("[TEST SUITE FAILED]");
            $finish(1);
        end
    end

endmodule
