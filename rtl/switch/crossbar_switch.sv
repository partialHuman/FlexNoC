// ==============================================================================
// File: crossbar_switch.sv
// Project: FlexNoC - Configurable Network-on-Chip
// Description: Fully parameterizable non-blocking crossbar switch with one-hot
//              select controls and formal mutual-exclusion invariant assertions.
// ==============================================================================

`timescale 1ns/1ps
`default_nettype none

module crossbar_switch #(
    parameter int unsigned DATA_WIDTH  = 32,
    parameter int unsigned NUM_INPUTS  = 5,
    parameter int unsigned NUM_OUTPUTS = 5
)(
    // Flattened array of input port data
    input  wire [(NUM_INPUTS*DATA_WIDTH)-1:0]  in_data,

    // Grant matrix: grant[out_idx][in_idx] is asserted when in_idx is routed to out_idx
    input  wire [(NUM_OUTPUTS*NUM_INPUTS)-1:0] grant_matrix,

    // Flattened array of output port data
    output logic [(NUM_OUTPUTS*DATA_WIDTH)-1:0] out_data
);

    // --------------------------------------------------------------------------
    // Combinational Multiplexer Array
    // --------------------------------------------------------------------------
    always_comb begin
        out_data = '0;

        for (int o = 0; o < int'(NUM_OUTPUTS); o++) begin
            for (int i = 0; i < int'(NUM_INPUTS); i++) begin
                if (grant_matrix[(o * NUM_INPUTS) + i]) begin
                    out_data[(o * DATA_WIDTH) +: DATA_WIDTH] = in_data[(i * DATA_WIDTH) +: DATA_WIDTH];
                end
            end
        end
    end

    // --------------------------------------------------------------------------
    // Simulation Mutual-Exclusion Invariant Checks
    // --------------------------------------------------------------------------
    `ifndef SYNTHESIS
    always_comb begin
        // Check 1: At most one input is granted to each output
        for (int o = 0; o < int'(NUM_OUTPUTS); o++) begin
            logic [NUM_INPUTS-1:0] out_grants;
            for (int i = 0; i < int'(NUM_INPUTS); i++) begin
                out_grants[i] = grant_matrix[(o * NUM_INPUTS) + i];
            end
            assert ($onehot0(out_grants)) else
                $error("[crossbar_switch] Invariant violation: output %0d granted to multiple inputs! grants=%b",
                       o, out_grants);
        end

        // Check 2: No input is granted to multiple outputs simultaneously
        for (int i = 0; i < int'(NUM_INPUTS); i++) begin
            logic [NUM_OUTPUTS-1:0] in_grants;
            for (int o = 0; o < int'(NUM_OUTPUTS); o++) begin
                in_grants[o] = grant_matrix[(o * NUM_INPUTS) + i];
            end
            assert ($onehot0(in_grants)) else
                $error("[crossbar_switch] Invariant violation: input %0d simultaneously granted to multiple outputs! grants=%b",
                       i, in_grants);
        end
    end
    `endif

endmodule

`default_nettype wire
