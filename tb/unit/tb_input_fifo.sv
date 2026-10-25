// ==============================================================================
// File: tb_input_fifo.sv
// Project: FlexNoC - Configurable Network-on-Chip
// Description: Self-checking unit testbench for input_fifo.sv.
//              Tests reset, empty/full limits, FWFT, simultaneous push/pop,
//              backpressure, and randomized golden-queue comparison.
// ==============================================================================

`timescale 1ns/1ps

module tb_input_fifo;

    localparam int unsigned DATA_WIDTH = 32;
    localparam int unsigned DEPTH      = 4;

    logic                  clk;
    logic                  rst_n;

    logic [DATA_WIDTH-1:0] push_data;
    logic                  push_valid;
    wire                   push_ready;

    wire  [DATA_WIDTH-1:0] pop_data;
    wire                   pop_valid;
    logic                  pop_ready;

    wire                   empty;
    wire                   full;
    wire  [$clog2(DEPTH+1)-1:0] count;

    // Golden reference model queue
    logic [DATA_WIDTH-1:0] golden_queue [$];

    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    // Clock generator (100 MHz, 10ns period)
    initial clk = 0;
    always #5 clk = ~clk;

    // Device Under Test (DUT)
    input_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .push_data (push_data),
        .push_valid(push_valid),
        .push_ready(push_ready),
        .pop_data  (pop_data),
        .pop_valid (pop_valid),
        .pop_ready (pop_ready),
        .empty     (empty),
        .full      (full),
        .count     (count)
    );

    task check(input string test_name, input bit condition);
        test_count++;
        if (condition) begin
            pass_count++;
            $display("[PASS] %s", test_name);
        end else begin
            fail_count++;
            $display("[FAIL] %s", test_name);
        end
    endtask

    // --------------------------------------------------------------------------
    // Test Sequence
    // --------------------------------------------------------------------------
    initial begin
        $display("==================================================");
        $display(" Starting Unit Tests: input_fifo");
        $display("==================================================");

        // Initialization
        rst_n      = 0;
        push_data  = '0;
        push_valid = 0;
        pop_ready  = 0;
        golden_queue.delete();

        // ----------------------------------------------------------------------
        // Test 1: Reset behavior
        // ----------------------------------------------------------------------
        repeat (4) @(posedge clk);
        check("Test 1a: Empty high after reset", empty === 1'b1);
        check("Test 1b: Full low after reset", full === 1'b0);
        check("Test 1c: Count is 0 after reset", count === 0);
        check("Test 1d: Push ready high after reset", push_ready === 1'b1);
        check("Test 1e: Pop valid low after reset", pop_valid === 1'b0);

        @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 2: Single Push and FWFT Pop
        // ----------------------------------------------------------------------
        @(negedge clk);
        push_data  = 32'hDEADBEEF;
        push_valid = 1;
        @(posedge clk);
        @(negedge clk);
        push_valid = 0;
        push_data  = '0;

        #1; // Sample combinational outputs
        check("Test 2a: Empty deasserted after 1 push", empty === 1'b0);
        check("Test 2b: Count is 1 after 1 push", count === 1);
        check("Test 2c: Pop valid asserted", pop_valid === 1'b1);
        check("Test 2d: FWFT data immediately visible", pop_data === 32'hDEADBEEF);

        // Now pop the flit
        @(negedge clk);
        pop_ready = 1;
        @(posedge clk);
        @(negedge clk);
        pop_ready = 0;
        #1;
        check("Test 2e: Empty reasserted after pop", empty === 1'b1);
        check("Test 2f: Count is 0 after pop", count === 0);

        // ----------------------------------------------------------------------
        // Test 3: Fill to Capacity
        // ----------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++) begin
            @(negedge clk);
            push_data  = 32'hA0000000 + i;
            push_valid = 1;
            @(posedge clk);
        end
        @(negedge clk);
        push_valid = 0;
        push_data  = '0;
        #1;
        check("Test 3a: Full asserted at capacity", full === 1'b1);
        check("Test 3b: Push ready deasserted when full", push_ready === 1'b0);
        check("Test 3c: Count matches DEPTH", count === DEPTH);

        // Attempt write when full (must be ignored)
        @(negedge clk);
        push_data  = 32'hFFFFFFFF;
        push_valid = 1;
        @(posedge clk);
        @(negedge clk);
        push_valid = 0;
        #1;
        check("Test 3d: Count still DEPTH after rejected write", count === DEPTH);

        // ----------------------------------------------------------------------
        // Test 4: Drain to Empty
        // ----------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++) begin
            #1;
            check($sformatf("Test 4_data[%0d]: Verified FIFO read", i), pop_data === (32'hA0000000 + i));
            @(negedge clk);
            pop_ready = 1;
            @(posedge clk);
        end
        @(negedge clk);
        pop_ready = 0;
        #1;
        check("Test 4a: Empty asserted after drain", empty === 1'b1);
        check("Test 4b: Count is 0 after drain", count === 0);

        // ----------------------------------------------------------------------
        // Test 5: Simultaneous Push and Pop
        // ----------------------------------------------------------------------
        // Pre-fill 2 flits
        @(negedge clk); push_data = 32'hB0000001; push_valid = 1; @(posedge clk);
        @(negedge clk); push_data = 32'hB0000002; push_valid = 1; @(posedge clk);
        @(negedge clk); push_valid = 0;
        #1;
        check("Test 5a: Pre-fill count is 2", count === 2);

        // Simultaneous push and pop for 5 cycles
        for (int i = 0; i < 5; i++) begin
            @(negedge clk);
            push_data  = 32'hC0000000 + i;
            push_valid = 1;
            pop_ready  = 1;
            @(posedge clk);
            #1;
            check($sformatf("Test 5_simul[%0d]: Count invariant maintained (count=2)", i), count === 2);
        end
        @(negedge clk);
        push_valid = 0;
        pop_ready  = 0;

        // Drain remaining
        while (!empty) begin
            @(negedge clk);
            pop_ready = 1;
            @(posedge clk);
        end
        @(negedge clk);
        pop_ready = 0;

        // ----------------------------------------------------------------------
        // Test 6: Randomized Push/Pop with Reference Model
        // ----------------------------------------------------------------------
        $display("--- Running 500 Randomized Push/Pop Cycles ---");
        golden_queue.delete();
        begin
            bit do_push;
            bit do_pop;
            logic [DATA_WIDTH-1:0] expected;

            for (int cyc = 0; cyc < 500; cyc++) begin
                @(negedge clk);
                do_push = ($urandom_range(0, 99) < 65) && push_ready;
                do_pop  = ($urandom_range(0, 99) < 60) && pop_valid;

                if (do_push) begin
                    push_data = $urandom();
                    push_valid = 1;
                    golden_queue.push_back(push_data);
                end else begin
                    push_valid = 0;
                end

                if (do_pop) begin
                    pop_ready = 1;
                    if (golden_queue.size() > 0) begin
                        expected = golden_queue.pop_front();
                        if (pop_data !== expected) begin
                            $display("[FAIL] Data mismatch at cycle %0d: got %h, expected %h",
                                     cyc, pop_data, expected);
                            fail_count++;
                        end
                    end
                end else begin
                    pop_ready = 0;
                end

                @(posedge clk);
            end

            // Drain and check remaining elements in golden queue
            @(negedge clk);
            push_valid = 0;
            while (golden_queue.size() > 0) begin
                if (pop_valid) begin
                    expected = golden_queue.pop_front();
                    if (pop_data !== expected) begin
                        $display("[FAIL] Data mismatch during final drain: got %h, expected %h",
                                 pop_data, expected);
                        fail_count++;
                    end
                    @(negedge clk);
                    pop_ready = 1;
                    @(posedge clk);
                end else begin
                    @(posedge clk);
                end
            end
        end
        @(negedge clk);
        pop_ready = 0;
        @(posedge clk);
        #1;
        check("Test 6: FIFO empty after randomized drain", empty === 1'b1);

        // ----------------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------------
        $display("==================================================");
        $display(" tb_input_fifo Complete: Total=%0d, Pass=%0d, Fail=%0d", 
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
