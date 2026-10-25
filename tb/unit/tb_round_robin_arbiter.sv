// ==============================================================================
// File: tb_round_robin_arbiter.sv
// Project: FlexNoC - Configurable Network-on-Chip
// Description: Self-checking unit testbench for round_robin_arbiter.sv.
//              Validates reset, single grants, priority rotation, backpressure stalls,
//              persistent contention, and mathematical fairness.
// ==============================================================================

`timescale 1ns/1ps

module tb_round_robin_arbiter;

    localparam int unsigned NUM_REQS = 5;

    logic                  clk;
    logic                  rst_n;
    logic [NUM_REQS-1:0]   req;
    logic                  update_enable;

    wire  [NUM_REQS-1:0]   grant;
    wire                   grant_valid;
    wire  [$clog2(NUM_REQS)-1:0] grant_idx;

    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    int grant_counts [NUM_REQS];

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT
    round_robin_arbiter #(
        .NUM_REQS(NUM_REQS)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .req          (req),
        .update_enable(update_enable),
        .grant        (grant),
        .grant_valid  (grant_valid),
        .grant_idx    (grant_idx)
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

    initial begin
        $display("==================================================");
        $display(" Starting Unit Tests: round_robin_arbiter");
        $display("==================================================");

        rst_n         = 0;
        req           = '0;
        update_enable = 0;

        // ----------------------------------------------------------------------
        // Test 1: Reset behavior
        // ----------------------------------------------------------------------
        repeat (3) @(posedge clk);
        #1;
        check("Test 1a: No grant during reset with no req", grant === 5'b00000);
        check("Test 1b: grant_valid low during reset", grant_valid === 1'b0);

        req = 5'b11111;
        #1;
        check("Test 1c: Reset keeps priority pointer deterministic", dut.priority_ptr === 0);

        @(posedge clk);
        rst_n = 1;
        req   = '0;
        @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 2: Single requests for each port
        // ----------------------------------------------------------------------
        for (int i = 0; i < NUM_REQS; i++) begin
            req = (1 << i);
            update_enable = 1;
            #1;
            check($sformatf("Test 2: Solo request port %0d granted immediately", i),
                  grant === (1 << i));
            @(posedge clk);
        end
        req = '0;
        update_enable = 0;
        @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 3: Downstream stall (update_enable = 0)
        // ----------------------------------------------------------------------
        // Request from both 1 and 2
        req = 5'b00110;
        update_enable = 0;
        #1;
        // Winner should be chosen and stay unchanged across clock edges without advancing
        begin
            logic [NUM_REQS-1:0] initial_grant;
            initial_grant = grant;
            check("Test 3a: Grant valid when stalled", grant_valid === 1'b1);
            repeat (5) @(posedge clk);
            #1;
            check("Test 3b: Grant remains completely stable while stalled", grant === initial_grant);
        end

        // Release stall
        update_enable = 1;
        @(posedge clk);
        #1;
        check("Test 3c: Grant rotated after update_enable asserted", grant === 5'b00100);
        @(posedge clk);
        req = '0;
        update_enable = 0;
        @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 4: Persistent Contention and Strict Mathematical Fairness
        // ----------------------------------------------------------------------
        // All 5 ports continuously request for 100 consecutive handshake cycles
        $display("--- Testing 100 Cycles of 5-Way Persistent Contention ---");
        for (int i = 0; i < NUM_REQS; i++) grant_counts[i] = 0;

        req           = 5'b11111;
        update_enable = 1;

        for (int cycle = 0; cycle < 100; cycle++) begin
            #1;
            check($sformatf("Cycle %0d: Exactly one grant active", cycle), $onehot(grant));
            grant_counts[grant_idx]++;
            @(posedge clk);
        end

        req           = '0;
        update_enable = 0;
        @(posedge clk);

        $display("Contention Grant Distribution over 100 cycles:");
        for (int i = 0; i < NUM_REQS; i++) begin
            $display("  Port %0d grants: %0d", i, grant_counts[i]);
            check($sformatf("Fairness: Port %0d received exactly 20 grants", i),
                  grant_counts[i] == 20);
        end

        // ----------------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------------
        $display("==================================================");
        $display(" tb_round_robin_arbiter Complete: Total=%0d, Pass=%0d, Fail=%0d",
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
