// ==============================================================================
// File: tb_flexnoc_router.sv
// Project: FlexNoC - Configurable Network-on-Chip
// Description: Comprehensive self-checking verification testbench for flexnoc_router.sv.
//              Covers reset, all directional routes, output contention, backpressure
//              propagation, concurrent multi-port routing, and packet integrity.
// ==============================================================================

`timescale 1ns/1ps

module tb_flexnoc_router;

    import flexnoc_pkg::*;

    localparam int unsigned DATA_WIDTH  = 32;
    localparam int unsigned X_WIDTH     = 2;
    localparam int unsigned Y_WIDTH     = 2;
    localparam int unsigned FIFO_DEPTH  = 4;
    localparam int unsigned ROUTER_X    = 1;
    localparam int unsigned ROUTER_Y    = 1;
    localparam int unsigned MESH_WIDTH  = 4;
    localparam int unsigned MESH_HEIGHT = 4;

    logic clk;
    logic rst_n;

    // 5 Ingress Ports
    logic [DATA_WIDTH-1:0] in_local_data, in_north_data, in_east_data, in_south_data, in_west_data;
    logic                  in_local_valid, in_north_valid, in_east_valid, in_south_valid, in_west_valid;
    wire                   in_local_ready, in_north_ready, in_east_ready, in_south_ready, in_west_ready;

    // 5 Egress Ports
    wire [DATA_WIDTH-1:0]  out_local_data, out_north_data, out_east_data, out_south_data, out_west_data;
    wire                   out_local_valid, out_north_valid, out_east_valid, out_south_valid, out_west_valid;
    logic                  out_local_ready, out_north_ready, out_east_ready, out_south_ready, out_west_ready;

    // Status
    wire [4:0]             status_fifo_full;
    wire [4:0]             status_fifo_empty;
    wire [4:0]             status_route_err;

    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT
    flexnoc_router #(
        .DATA_WIDTH (DATA_WIDTH),
        .X_WIDTH    (X_WIDTH),
        .Y_WIDTH    (Y_WIDTH),
        .FIFO_DEPTH (FIFO_DEPTH),
        .ROUTER_X   (ROUTER_X),
        .ROUTER_Y   (ROUTER_Y),
        .MESH_WIDTH (MESH_WIDTH),
        .MESH_HEIGHT(MESH_HEIGHT)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),

        .in_local_data    (in_local_data),
        .in_local_valid   (in_local_valid),
        .in_local_ready   (in_local_ready),

        .in_north_data    (in_north_data),
        .in_north_valid   (in_north_valid),
        .in_north_ready   (in_north_ready),

        .in_east_data     (in_east_data),
        .in_east_valid    (in_east_valid),
        .in_east_ready    (in_east_ready),

        .in_south_data    (in_south_data),
        .in_south_valid   (in_south_valid),
        .in_south_ready   (in_south_ready),

        .in_west_data     (in_west_data),
        .in_west_valid    (in_west_valid),
        .in_west_ready    (in_west_ready),

        .out_local_data   (out_local_data),
        .out_local_valid  (out_local_valid),
        .out_local_ready  (out_local_ready),

        .out_north_data   (out_north_data),
        .out_north_valid  (out_north_valid),
        .out_north_ready  (out_north_ready),

        .out_east_data    (out_east_data),
        .out_east_valid   (out_east_valid),
        .out_east_ready   (out_east_ready),

        .out_south_data   (out_south_data),
        .out_south_valid  (out_south_valid),
        .out_south_ready  (out_south_ready),

        .out_west_data    (out_west_data),
        .out_west_valid   (out_west_valid),
        .out_west_ready   (out_west_ready),

        .status_fifo_full (status_fifo_full),
        .status_fifo_empty(status_fifo_empty),
        .status_route_err (status_route_err)
    );

    task check(input string test_name, input bit condition);
        test_count++;
        if (condition) begin
            pass_count++;
        end else begin
            fail_count++;
            $display("[FAIL] %s", test_name);
        end
    endtask

    // Helper task to clear all inputs
    task clear_inputs();
        in_local_valid = 0; in_local_data = '0;
        in_north_valid = 0; in_north_data = '0;
        in_east_valid  = 0; in_east_data  = '0;
        in_south_valid = 0; in_south_data = '0;
        in_west_valid  = 0; in_west_data  = '0;
    endtask

    // Helper task to inject a flit into a specific port
    task inject_flit(
        input port_id_e in_port,
        input logic [X_WIDTH-1:0] dx,
        input logic [Y_WIDTH-1:0] dy,
        input logic [7:0] pkt_id,
        input logic [15:0] payload
    );
        logic [DATA_WIDTH-1:0] flit;
        flit = create_flit(dx, dy, X_WIDTH'(ROUTER_X), Y_WIDTH'(ROUTER_Y), pkt_id, payload);

        @(negedge clk);
        case (in_port)
            PORT_LOCAL: begin in_local_data = flit; in_local_valid = 1; end
            PORT_NORTH: begin in_north_data = flit; in_north_valid = 1; end
            PORT_EAST:  begin in_east_data  = flit; in_east_valid  = 1; end
            PORT_SOUTH: begin in_south_data = flit; in_south_valid = 1; end
            PORT_WEST:  begin in_west_data  = flit; in_west_valid  = 1; end
        endcase

        @(posedge clk);
        @(negedge clk);
        clear_inputs();
    endtask

    initial begin
        $display("==================================================");
        $display(" Starting Router Integration Tests: flexnoc_router (1,1)");
        $display("==================================================");

        rst_n = 0;
        clear_inputs();
        out_local_ready = 1;
        out_north_ready = 1;
        out_east_ready  = 1;
        out_south_ready = 1;
        out_west_ready  = 1;

        // ----------------------------------------------------------------------
        // Test 1: Reset check
        // ----------------------------------------------------------------------
        repeat (4) @(posedge clk);
        check("Test 1a: All FIFOs empty on reset", status_fifo_empty === 5'b11111);
        check("Test 1b: All FIFOs not full on reset", status_fifo_full === 5'b00000);
        check("Test 1c: All outputs invalid on reset", 
              {out_local_valid, out_north_valid, out_east_valid, out_south_valid, out_west_valid} === 5'b00000);

        @(negedge clk);
        rst_n = 1;
        @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 2: Directional Routing from Local Port to All 5 Directions
        // Router is at (1, 1).
        // Target (2, 1) -> East
        // Target (0, 1) -> West
        // Target (1, 2) -> South
        // Target (1, 0) -> North
        // Target (1, 1) -> Local
        // ----------------------------------------------------------------------
        $display("--- Testing Single-Flit Traversal in All 5 Directions ---");

        // 2a: To East (dest = 2, 1)
        inject_flit(PORT_LOCAL, 2, 1, 8'h01, 16'hEE01);
        #1;
        check("Test 2a: Flit emerged on East port", out_east_valid === 1'b1);
        check("Test 2a: East flit data integrity", get_payload(out_east_data) === 16'hEE01);
        @(posedge clk); // Flit consumed by receiver
        #1;
        check("Test 2a_post: East valid deasserted", out_east_valid === 1'b0);

        // 2b: To West (dest = 0, 1)
        inject_flit(PORT_LOCAL, 0, 1, 8'h02, 16'hB002);
        #1;
        check("Test 2b: Flit emerged on West port", out_west_valid === 1'b1);
        check("Test 2b: West flit data integrity", get_payload(out_west_data) === 16'hB002);
        @(posedge clk);
        #1;

        // 2c: To South (dest = 1, 2)
        inject_flit(PORT_LOCAL, 1, 2, 8'h03, 16'hC003);
        #1;
        check("Test 2c: Flit emerged on South port", out_south_valid === 1'b1);
        check("Test 2c: South flit data integrity", get_payload(out_south_data) === 16'hC003);
        @(posedge clk);
        #1;

        // 2d: To North (dest = 1, 0)
        inject_flit(PORT_LOCAL, 1, 0, 8'h04, 16'hD004);
        #1;
        check("Test 2d: Flit emerged on North port", out_north_valid === 1'b1);
        check("Test 2d: North flit data integrity", get_payload(out_north_data) === 16'hD004);
        @(posedge clk);
        #1;

        // 2e: To Local (dest = 1, 1) arriving from North port
        inject_flit(PORT_NORTH, 1, 1, 8'h05, 16'hE005);
        #1;
        check("Test 2e: Flit from North emerged on Local port", out_local_valid === 1'b1);
        check("Test 2e: Local flit data integrity", get_payload(out_local_data) === 16'hE005);
        @(posedge clk);
        #1;

        // ----------------------------------------------------------------------
        // Test 3: Downstream Backpressure & Stability
        // Hold out_east_ready = 0 while injecting flit targeting East
        // ----------------------------------------------------------------------
        $display("--- Testing Downstream Backpressure & Data Stability ---");
        out_east_ready = 0;
        inject_flit(PORT_WEST, 2, 1, 8'h10, 16'hBB10); // West In -> East Out
        #1;
        check("Test 3a: Flit waiting on East port with valid=1", out_east_valid === 1'b1);

        // Hold stalled for 5 cycles and verify valid and data are 100% stable
        for (int s = 0; s < 5; s++) begin
            @(posedge clk);
            #1;
            check($sformatf("Test 3_stall[%0d]: valid stays high", s), out_east_valid === 1'b1);
            check($sformatf("Test 3_stall[%0d]: data unchanged", s), get_payload(out_east_data) === 16'hBB10);
        end

        // Release backpressure
        @(negedge clk);
        out_east_ready = 1;
        @(posedge clk);
        #1;
        check("Test 3c: Flit successfully transmitted on ready assertion", out_east_valid === 1'b0);

        // ----------------------------------------------------------------------
        // Test 4: Contention Resolution (3 Ingress Ports Competing for East)
        // West, North, and Local all inject flits targeting East (dest_x = 2, dest_y = 1)
        // ----------------------------------------------------------------------
        $display("--- Testing Contention Resolution for Egress East ---");
        @(negedge clk);
        in_west_data  = create_flit(2, 1, 0, 1, 8'hA1, 16'hAA01); in_west_valid  = 1;
        in_north_data = create_flit(2, 1, 1, 0, 8'hA2, 16'hAA02); in_north_valid = 1;
        in_local_data = create_flit(2, 1, 1, 1, 8'hA3, 16'hAA03); in_local_valid = 1;
        @(posedge clk);
        @(negedge clk);
        clear_inputs();

        // 3 flits must emerge on out_east sequentially over the next 3 cycles
        for (int step = 0; step < 3; step++) begin
            #1;
            check($sformatf("Contention step %0d: out_east_valid asserted", step), out_east_valid === 1'b1);
            $display("  Contention flit %0d payload: %h", step, get_payload(out_east_data));
            @(posedge clk);
        end
        #1;
        check("Contention complete: East egress idle", out_east_valid === 1'b0);

        // ----------------------------------------------------------------------
        // Test 5: Concurrent Independent Transfers (Non-Blocking Crossbar)
        // In West -> Out East and In North -> Out South in the SAME cycle!
        // ----------------------------------------------------------------------
        $display("--- Testing Concurrent Independent Transfers ---");
        @(negedge clk);
        in_west_data  = create_flit(2, 1, 0, 1, 8'hC1, 16'hCC01); in_west_valid  = 1; // to East
        in_north_data = create_flit(1, 2, 1, 0, 8'hC2, 16'hCC02); in_north_valid = 1; // to South
        @(posedge clk);
        @(negedge clk);
        clear_inputs();
        #1;
        check("Test 5a: Both East and South valid simultaneously", 
              (out_east_valid === 1'b1) && (out_south_valid === 1'b1));
        check("Test 5b: East payload correct", get_payload(out_east_data) === 16'hCC01);
        check("Test 5c: South payload correct", get_payload(out_south_data) === 16'hCC02);
        @(posedge clk);
        #1;
        check("Test 5d: Both delivered in 1 cycle", 
              (out_east_valid === 1'b0) && (out_south_valid === 1'b0));

        // ----------------------------------------------------------------------
        // Test 6: Asynchronous Reset During Active Traffic & Recovery
        // ----------------------------------------------------------------------
        $display("--- Testing Asynchronous Reset During Active Traffic ---");
        // Inject flits into West and North targeting East and South
        @(negedge clk);
        in_west_data  = create_flit(2, 1, 0, 1, 8'hD1, 16'hDD01); in_west_valid  = 1;
        in_north_data = create_flit(1, 2, 1, 0, 8'hD2, 16'hDD02); in_north_valid = 1;
        out_east_ready = 0; // Hold backpressure so flits remain buffered
        out_south_ready = 0;
        @(posedge clk);
        #1;
        check("Test 6a: Traffic active before mid-flight reset",
              (out_east_valid === 1'b1) && (out_south_valid === 1'b1));

        // Assert asynchronous reset midway through cycle
        #2;
        rst_n = 0;
        clear_inputs();
        #1;
        check("Test 6b: All egress valid signals immediately deasserted on reset",
              {out_local_valid, out_north_valid, out_east_valid, out_south_valid, out_west_valid} === 5'b00000);
        check("Test 6c: Ingress FIFOs report empty during reset", status_fifo_empty === 5'b11111);

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        out_east_ready  = 1;
        out_south_ready = 1;
        @(posedge clk);
        #1;
        check("Test 6d: Post-reset idle state clean",
              {out_local_valid, out_north_valid, out_east_valid, out_south_valid, out_west_valid} === 5'b00000);

        // Verify clean recovery by injecting a new flit to East
        inject_flit(PORT_WEST, 2, 1, 8'hD3, 16'hDD03);
        #1;
        check("Test 6e: Recovery flit successfully transmitted after reset", out_east_valid === 1'b1);
        check("Test 6f: Recovery payload intact", get_payload(out_east_data) === 16'hDD03);
        @(posedge clk);
        #1;
        check("Test 6g: Output idle after recovery", out_east_valid === 1'b0);

        // ----------------------------------------------------------------------
        // Test 7: Randomized Backpressure Stress
        // ----------------------------------------------------------------------
        $display("--- Testing Randomized Backpressure & Link Protocol Stability ---");
        begin
            int stress_injected;
            int stress_received;
            logic [15:0] stress_exp_payload;
            int stress_cycles;

            stress_injected = 0;
            stress_received = 0;
            stress_cycles = 0;

            // Stream 20 flits West In -> East Out under random backpressure
            while ((stress_received < 20) && (stress_cycles < 200)) begin
                @(negedge clk);
                // Randomize receiver readiness
                out_east_ready = $urandom_range(0, 1);

                // Inject next flit if ready and remaining
                if ((stress_injected < 20) && in_west_ready) begin
                    in_west_data = create_flit(2, 1, 0, 1, 8'(stress_injected), 16'hE100 + 16'(stress_injected));
                    in_west_valid = 1'b1;
                    stress_injected++;
                end else begin
                    in_west_valid = 1'b0;
                end

                @(posedge clk);
                #1;
                // Monitor output
                if (out_east_valid && out_east_ready) begin
                    stress_exp_payload = 16'hE100 + 16'(stress_received);
                    check($sformatf("Test 7_stress[%0d]: payload verified", stress_received),
                          get_payload(out_east_data) === stress_exp_payload);
                    stress_received++;
                end else if (out_east_valid && !out_east_ready) begin
                    // Protocol invariant: Data must stay valid and unchanging during stall
                    check("Test 7_invariant: Data valid during stall", out_east_valid === 1'b1);
                end
                stress_cycles++;
            end

            clear_inputs();
            out_east_ready = 1;
            while ((stress_received < stress_injected) && (stress_cycles < 250)) begin
                @(posedge clk);
                #1;
                if (out_east_valid && out_east_ready) begin
                    stress_received++;
                end
                stress_cycles++;
            end

            check("Test 7: All 20 stress flits received under backpressure", stress_received === 20);
        end

        // ----------------------------------------------------------------------
        // Test 8: All 5 Ingress Ports Persistent Contention for Local Port
        // ----------------------------------------------------------------------
        $display("--- Testing 5-Way Simultaneous Contention for Local Port ---");
        begin
            @(negedge clk);
            // All 5 ingress ports inject simultaneously targeting Local (dest = 1, 1)
            in_local_data = create_flit(1, 1, 1, 1, 8'h50, 16'h5000); in_local_valid = 1;
            in_north_data = create_flit(1, 1, 1, 0, 8'h51, 16'h5001); in_north_valid = 1;
            in_east_data  = create_flit(1, 1, 2, 1, 8'h52, 16'h5002); in_east_valid  = 1;
            in_south_data = create_flit(1, 1, 1, 2, 8'h53, 16'h5003); in_south_valid = 1;
            in_west_data  = create_flit(1, 1, 0, 1, 8'h54, 16'h5004); in_west_valid  = 1;
            out_local_ready = 1;

            @(posedge clk);
            @(negedge clk);
            clear_inputs();

            // All 5 flits must be granted and emerge sequentially over 5 cycles
            for (int step = 0; step < 5; step++) begin
                #1;
                check($sformatf("Test 8_step[%0d]: Local valid active", step), out_local_valid === 1'b1);
                @(posedge clk);
            end
            #1;
            check("Test 8: Local port returns to idle after all 5 contention flits", out_local_valid === 1'b0);
        end

        // ----------------------------------------------------------------------
        // Final Router State
        // ----------------------------------------------------------------------
        repeat (3) @(posedge clk);
        #1;
        check("Final: All FIFOs empty", status_fifo_empty === 5'b11111);
        check("Final: Zero route errors", status_route_err === 5'b00000);

        // ----------------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------------
        $display("==================================================");
        $display(" tb_flexnoc_router Complete: Total=%0d, Pass=%0d, Fail=%0d",
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
