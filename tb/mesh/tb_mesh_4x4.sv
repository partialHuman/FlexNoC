// ==============================================================================
// File: tb_mesh_4x4.sv
// Project: FlexNoC - Configurable Network-on-Chip
// Description: Comprehensive verification testbench for 4x4 mesh_top (16 nodes).
//              Tests corner-to-corner 6-hop routing, diagonal crossings,
//              same-row/same-column traverses, and randomized 16-node traffic.
// ==============================================================================

`timescale 1ns/1ps

module tb_mesh_4x4;

    import flexnoc_pkg::*;

    localparam int unsigned DATA_WIDTH  = 32;
    localparam int unsigned X_WIDTH     = 2;
    localparam int unsigned Y_WIDTH     = 2;
    localparam int unsigned FIFO_DEPTH  = 4;
    localparam int unsigned MESH_WIDTH  = 4;
    localparam int unsigned MESH_HEIGHT = 4;
    localparam int unsigned NUM_NODES   = MESH_WIDTH * MESH_HEIGHT; // 16 nodes

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

    // Unified global received packet queue: [47:32]=dest_node, [31:0]=flit
    logic [47:0] global_rx_queue [$];

    // Clock generator (100 MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT: 4x4 Mesh (16 Nodes)
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
    // Autonomous Receiver Monitors for all 16 nodes
    // --------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            for (int n = 0; n < 16; n++) begin
                if (out_local_valid[n] && out_local_ready[n]) begin
                    global_rx_queue.push_back({16'(n), out_local_data[(n*DATA_WIDTH) +: DATA_WIDTH]});
                    packets_delivered++;
                end
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

    // Inject packet into source node
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
    task verify_packet(
        input int dest_node,
        input int expected_src,
        input logic [7:0] expected_pkt_id,
        input logic [15:0] expected_payload,
        input string desc
    );
        int timeout;
        logic [DATA_WIDTH-1:0] flit;
        bit found;
        int i;
        logic [47:0] item;

        timeout = 100;
        found = 0;

        while (timeout > 0 && !found) begin
            for (i = 0; i < global_rx_queue.size() && !found; i = i + 1) begin
                item = global_rx_queue[i];
                if (item[47:32] == 16'(dest_node)) begin
                    flit = item[31:0];
                    global_rx_queue.delete(i);
                    found = 1;
                end
            end
            if (!found) begin
                @(posedge clk);
                timeout--;
            end
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
        $display(" Starting 4x4 Mesh Integration Tests: tb_mesh_4x4");
        $display("==================================================");

        rst_n           = 0;
        in_local_data   = '0;
        in_local_valid  = '0;
        out_local_ready = {NUM_NODES{1'b1}};

        // Reset check
        repeat (5) @(posedge clk);
        check("Test 1: Zero error flags after reset", status_err === {NUM_NODES{1'b0}});
        check("Test 1: All out_valid low after reset", out_local_valid === {NUM_NODES{1'b0}});

        @(negedge clk);
        rst_n = 1;
        @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 2: Corner-to-Corner 6-Hop Traversal
        // ----------------------------------------------------------------------
        $display("--- Testing 4 Corner-to-Corner 6-Hop Traversal Routes ---");
        // (0,0) -> (3,3): Node 0 to Node 15 (East x3, South x3)
        inject_packet(0, 15, 8'h01, 16'hC001);
        verify_packet(15, 0, 8'h01, 16'hC001, "Corner Node (0,0)->(3,3)");

        // (3,3) -> (0,0): Node 15 to Node 0 (West x3, North x3)
        inject_packet(15, 0, 8'h02, 16'hC002);
        verify_packet(0, 15, 8'h02, 16'hC002, "Corner Node (3,3)->(0,0)");

        // (3,0) -> (0,3): Node 3 to Node 12 (West x3, South x3)
        inject_packet(3, 12, 8'h03, 16'hC003);
        verify_packet(12, 3, 8'h03, 16'hC003, "Corner Node (3,0)->(0,3)");

        // (0,3) -> (3,0): Node 12 to Node 3 (East x3, North x3)
        inject_packet(12, 3, 8'h04, 16'hC004);
        verify_packet(3, 12, 8'h04, 16'hC004, "Corner Node (0,3)->(3,0)");

        // ----------------------------------------------------------------------
        // Test 3: Row & Column Sweeps
        // ----------------------------------------------------------------------
        $display("--- Testing Row Traversal (Node 0 to 1, 2, 3) ---");
        for (int x = 1; x < 4; x++) begin
            inject_packet(0, x, 8'h10 + 8'(x), 16'h1000 + 16'(x));
            verify_packet(x, 0, 8'h10 + 8'(x), 16'h1000 + 16'(x), $sformatf("Row Node 0->%0d", x));
        end

        $display("--- Testing Column Traversal (Node 0 to 4, 8, 12) ---");
        for (int y = 1; y < 4; y++) begin
            int dst;
            dst = y * 4;
            inject_packet(0, dst, 8'h20 + 8'(y), 16'h2000 + 16'(y));
            verify_packet(dst, 0, 8'h20 + 8'(y), 16'h2000 + 16'(y), $sformatf("Col Node 0->%0d", dst));
        end

        // ----------------------------------------------------------------------
        // Test 4: Randomized Traffic (100 packets across all 16 nodes)
        // ----------------------------------------------------------------------
        $display("--- Running 100 Randomized Multi-Hop Packets ---");
        begin
            int src;
            int dst;
            logic [7:0] pid;
            logic [15:0] pld;

            for (int p = 0; p < 100; p++) begin
                src = $urandom_range(0, 15);
                dst = $urandom_range(0, 15);
                pid = 8'h30 + 8'(p);
                pld = 16'hF000 + 16'(p);

                inject_packet(src, dst, pid, pld);
                verify_packet(dst, src, pid, pld, $sformatf("Rand pkt %0d (N%0d->N%0d)", p, src, dst));
            end
        end

        // ----------------------------------------------------------------------
        // Final Scoreboard Verification
        // ----------------------------------------------------------------------
        repeat (10) @(posedge clk);
        #1;
        $display("Final 4x4 Accounting: Injected=%0d, Delivered=%0d", 
                 packets_injected, packets_delivered);
        check("Scoreboard: 100% of packets delivered across 4x4 mesh", 
              packets_injected == packets_delivered);
        check("Final: All local outputs idle", out_local_valid === {NUM_NODES{1'b0}});
        check("Final: Zero error status", status_err === {NUM_NODES{1'b0}});

        // ----------------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------------
        $display("==================================================");
        $display(" tb_mesh_4x4 Complete: Total=%0d, Pass=%0d, Fail=%0d",
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
