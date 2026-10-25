// ==============================================================================
// File: tb_crossbar_switch.sv
// Project: FlexNoC - Configurable Network-on-Chip
// Description: Self-checking unit testbench for crossbar_switch.sv.
//              Validates 5x5 data multiplexing, simultaneous permutations,
//              and data isolation.
// ==============================================================================

`timescale 1ns/1ps

module tb_crossbar_switch;

    localparam int unsigned DATA_WIDTH  = 32;
    localparam int unsigned NUM_INPUTS  = 5;
    localparam int unsigned NUM_OUTPUTS = 5;

    logic [(NUM_INPUTS*DATA_WIDTH)-1:0]  in_data;
    logic [(NUM_OUTPUTS*NUM_INPUTS)-1:0] grant_matrix;
    wire  [(NUM_OUTPUTS*DATA_WIDTH)-1:0] out_data;

    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    // DUT
    crossbar_switch #(
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_INPUTS (NUM_INPUTS),
        .NUM_OUTPUTS(NUM_OUTPUTS)
    ) dut (
        .in_data     (in_data),
        .grant_matrix(grant_matrix),
        .out_data    (out_data)
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

    function automatic void set_input(input int idx, input logic [DATA_WIDTH-1:0] val);
        in_data[(idx*DATA_WIDTH) +: DATA_WIDTH] = val;
    endfunction

    function automatic logic [DATA_WIDTH-1:0] get_output(input int idx);
        return out_data[(idx*DATA_WIDTH) +: DATA_WIDTH];
    endfunction

    function automatic void set_grant(input int out_idx, input int in_idx);
        grant_matrix[(out_idx*NUM_INPUTS) + in_idx] = 1'b1;
    endfunction

    initial begin
        $display("==================================================");
        $display(" Starting Unit Tests: crossbar_switch");
        $display("==================================================");

        in_data      = '0;
        grant_matrix = '0;
        #10;

        // ----------------------------------------------------------------------
        // Test 1: Zero grants -> all outputs zero
        // ----------------------------------------------------------------------
        for (int o = 0; o < NUM_OUTPUTS; o++) begin
            check($sformatf("Test 1: Output %0d is 0 when ungranted", o), get_output(o) === '0);
        end

        // ----------------------------------------------------------------------
        // Test 2: Point-to-point sweep: Route each Input i to each Output o
        // ----------------------------------------------------------------------
        for (int i = 0; i < NUM_INPUTS; i++) begin
            set_input(i, 32'h1000_0000 + (i * 32'h0100_0000));
        end

        for (int o = 0; o < NUM_OUTPUTS; o++) begin
            for (int i = 0; i < NUM_INPUTS; i++) begin
                grant_matrix = '0;
                set_grant(o, i);
                #10;
                check($sformatf("Route In %0d -> Out %0d data match", i, o),
                      get_output(o) === (32'h1000_0000 + (i * 32'h0100_0000)));
            end
        end

        // ----------------------------------------------------------------------
        // Test 3: Full 5-Way Reverse Permutation
        // In 0 -> Out 4, In 1 -> Out 3, In 2 -> Out 2, In 3 -> Out 1, In 4 -> Out 0
        // ----------------------------------------------------------------------
        grant_matrix = '0;
        for (int i = 0; i < 5; i++) begin
            set_input(i, 32'hCAFE_0000 + i);
            set_grant(4 - i, i);
        end
        #10;
        for (int o = 0; o < 5; o++) begin
            check($sformatf("Permutation Out %0d gets In %0d", o, 4 - o),
                  get_output(o) === (32'hCAFE_0000 + (4 - o)));
        end

        // ----------------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------------
        $display("==================================================");
        $display(" tb_crossbar_switch Complete: Total=%0d, Pass=%0d, Fail=%0d",
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
