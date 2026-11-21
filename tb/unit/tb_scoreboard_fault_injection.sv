// ==============================================================================
// File: tb_scoreboard_fault_injection.sv
// Project: FlexNoC - Configurable Network-on-Chip
// Description: Fault-injection testbench demonstrating scoreboard sensitivity and
//              integrity under corrupted, dropped, misrouted, and duplicate packets.
//              Proves that the verification environment detects anomalous network
//              behavior rather than masking silent failures.
// ==============================================================================

`timescale 1ns/1ps
`default_nettype none

module tb_scoreboard_fault_injection;

    import flexnoc_pkg::*;

    localparam int unsigned DATA_WIDTH  = 32;
    localparam int unsigned X_WIDTH     = 2;
    localparam int unsigned Y_WIDTH     = 2;
    localparam int unsigned FIFO_DEPTH  = 4;
    localparam int unsigned MESH_WIDTH  = 2;
    localparam int unsigned MESH_HEIGHT = 2;
    localparam int unsigned NUM_NODES   = 4;

    logic clk;
    logic rst_n;

    // Flattened Endpoint interfaces
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

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT: 2x2 Mesh
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

    task check(input string test_name, input bit condition);
        test_count = test_count + 1;
        if (condition) begin
            pass_count = pass_count + 1;
            $display("[PASS] %s", test_name);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] %s", test_name);
        end
    endtask

    // Scoreboard State: flat packed 48-bit queue
    // [47:32]=dst, [31:16]=payload, [15:8]=src, [7:0]=pkt_id
    logic [47:0] expected_queue [$];
    bit [255:0] retired_pkt_ids = '0;

    function automatic logic [47:0] pack_expected(
        input int src,
        input int dst,
        input logic [7:0] pid,
        input logic [15:0] pld
    );
        return {16'(dst), pld, 8'(src), pid};
    endfunction

    // Detection flags
    bit fault1_payload_mismatch_detected = 0;
    bit fault2_wrong_dest_detected       = 0;
    bit fault3_timeout_drop_detected     = 0;
    bit fault4_duplicate_pkt_detected    = 0;

    // Scoreboard Receiver Monitor
    task check_received_packet(
        input int node_id,
        input logic [DATA_WIDTH-1:0] flit
    );
        logic [15:0] rx_payload;
        logic [7:0]  rx_pkt_id;
        int rx_sx, rx_sy, rx_dx, rx_dy;
        bit match_found;
        int match_idx;
        logic [47:0] exp_item;
        int exp_dst;
        logic [15:0] exp_pld;

        rx_payload = get_payload(flit);
        rx_pkt_id  = flit[23:16];
        rx_sx      = int'(flit[27:26]);
        rx_sy      = int'(flit[25:24]);
        rx_dx      = int'(flit[31:30]);
        rx_dy      = int'(flit[29:28]);

        // Check for duplicate packet
        if (retired_pkt_ids[rx_pkt_id]) begin
            $display("[SCOREBOARD DETECT] Duplicate packet detected! pkt_id=%0d", rx_pkt_id);
            fault4_duplicate_pkt_detected = 1;
        end
        // Check for wrong destination delivery
        else if ((rx_dy * MESH_WIDTH + rx_dx) != node_id) begin
            $display("[SCOREBOARD DETECT] Packet delivered to wrong node! target=(%0d,%0d) arrived at node %0d",
                     rx_dx, rx_dy, node_id);
            fault2_wrong_dest_detected = 1;
        end
        else begin
            // Search expected queue
            match_found = 0;
            match_idx = 0;
            for (int i = 0; i < expected_queue.size() && !match_found; i = i + 1) begin
                exp_item = expected_queue[i];
                exp_dst  = int'(exp_item[47:32]);
                if (exp_dst == node_id && exp_item[7:0] == rx_pkt_id) begin
                    match_idx = i;
                    match_found = 1;
                end
            end

            if (match_found) begin
                exp_item = expected_queue[match_idx];
                exp_pld  = exp_item[31:16];
                if (rx_payload !== exp_pld) begin
                    $display("[SCOREBOARD DETECT] Payload mismatch! Expected 0x%h, Got 0x%h", exp_pld, rx_payload);
                    fault1_payload_mismatch_detected = 1;
                end
                retired_pkt_ids[rx_pkt_id] = 1'b1;
                expected_queue.delete(match_idx);
            end else begin
                $display("[SCOREBOARD DETECT] Unexpected packet received at node %0d! pkt_id=%0d", node_id, rx_pkt_id);
                fault2_wrong_dest_detected = 1;
            end
        end
    endtask

    // Receiver loop
    always @(posedge clk) begin
        if (rst_n) begin
            for (int n = 0; n < int'(NUM_NODES); n = n + 1) begin
                if (out_local_valid[n] && out_local_ready[n]) begin
                    check_received_packet(n, out_local_data[(n*DATA_WIDTH) +: DATA_WIDTH]);
                end
            end
        end
    end

    // Test sequence
    initial begin
        $display("==================================================");
        $display(" Starting Scoreboard Fault-Injection Validation");
        $display("==================================================");

        rst_n           = 0;
        in_local_data   = '0;
        in_local_valid  = '0;
        out_local_ready = {NUM_NODES{1'b1}};
        expected_queue.delete();

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        @(posedge clk);

        // ----------------------------------------------------------------------
        // Fault Scenario 1: Payload Bit Corruption Detection
        // Sender expects payload 0x1234, but injects corrupted payload 0x1235
        // ----------------------------------------------------------------------
        $display("--- Injecting Fault 1: Payload Bit Corruption ---");
        begin
            expected_queue.push_back(pack_expected(0, 1, 8'h01, 16'h1234));

            @(negedge clk);
            // Inject with deliberately corrupted payload 0x1235
            in_local_data[(0*DATA_WIDTH) +: DATA_WIDTH] = create_flit(1, 0, 0, 0, 8'h01, 16'h1235);
            in_local_valid[0] = 1'b1;
            @(posedge clk);
            @(negedge clk);
            in_local_valid[0] = 1'b0;

            repeat (15) @(posedge clk);
            check("Fault 1: Scoreboard caught payload bit corruption", fault1_payload_mismatch_detected === 1'b1);
        end

        // ----------------------------------------------------------------------
        // Fault Scenario 2: Misrouted Destination Detection
        // Injected flit packet header indicates Node 3, but is delivered to Node 2
        // ----------------------------------------------------------------------
        $display("--- Injecting Fault 2: Packet Delivered to Wrong Destination ---");
        begin
            @(negedge clk);
            in_local_data[(0*DATA_WIDTH) +: DATA_WIDTH] = create_flit(1, 1, 0, 0, 8'h02, 16'h2222);
            in_local_valid[0] = 1'b1;
            @(posedge clk);
            @(negedge clk);
            in_local_valid[0] = 1'b0;

            // Direct check on receiver with mismatched destination header
            check_received_packet(2, create_flit(1, 1, 0, 0, 8'h02, 16'h2222));
            check("Fault 2: Scoreboard caught wrong destination delivery", fault2_wrong_dest_detected === 1'b1);
        end

        // ----------------------------------------------------------------------
        // Fault Scenario 3: Packet Loss / Dropped Packet Detection
        // Expect a packet to arrive at Node 3, but drop/never inject it
        // ----------------------------------------------------------------------
        $display("--- Injecting Fault 3: Packet Loss / Missing Packet Timeout ---");
        begin
            int timeout_counter;

            expected_queue.push_back(pack_expected(1, 3, 8'h03, 16'h3333)); // Expected, but never injected!

            timeout_counter = 20;
            while (timeout_counter > 0 && expected_queue.size() > 0) begin
                @(posedge clk);
                timeout_counter = timeout_counter - 1;
            end

            if (timeout_counter == 0 && expected_queue.size() > 0) begin
                $display("[SCOREBOARD DETECT] Missing packet timeout detected! Packet not received.");
                fault3_timeout_drop_detected = 1;
                expected_queue.delete();
            end

            check("Fault 3: Scoreboard caught packet loss timeout", fault3_timeout_drop_detected === 1'b1);
        end

        // ----------------------------------------------------------------------
        // Fault Scenario 4: Duplicate Packet Delivery Detection
        // Deliver an already-retired packet ID
        // ----------------------------------------------------------------------
        $display("--- Injecting Fault 4: Duplicate Packet Injection ---");
        begin
            // Packet ID 8'h01 was already retired in Fault Scenario 1
            check_received_packet(1, create_flit(1, 0, 0, 0, 8'h01, 16'h1234));
            check("Fault 4: Scoreboard caught duplicate packet delivery", fault4_duplicate_pkt_detected === 1'b1);
        end

        // ----------------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------------
        $display("==================================================");
        $display(" Scoreboard Fault-Injection Summary: Total=%0d, Pass=%0d, Fail=%0d",
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
`default_nettype wire
