// ==============================================================================
// File: round_robin_arbiter.sv
// Project: FlexNoC - Configurable Network-on-Chip
// Description: Parameterized starvation-free round-robin arbiter.
//              Grants at most one requesting client per cycle.
//              Priority pointer advances strictly upon a confirmed downstream
//              handshake (update_enable asserted).
// ==============================================================================

`timescale 1ns/1ps
`default_nettype none

module round_robin_arbiter #(
    parameter int unsigned NUM_REQS = 5
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Request vector from clients
    input  wire [NUM_REQS-1:0]    req,

    // Handshake feedback: advance priority pointer only when downstream accepts
    input  wire                   update_enable,

    // One-hot grant vector and active grant flag
    output logic [NUM_REQS-1:0]   grant,
    output logic                  grant_valid,
    output logic [$clog2(NUM_REQS)-1:0] grant_idx
);

    localparam int unsigned PTR_WIDTH = (NUM_REQS > 1) ? $clog2(NUM_REQS) : 1;

    logic [PTR_WIDTH-1:0] priority_ptr;
    logic [NUM_REQS-1:0]  mask;
    logic [NUM_REQS-1:0]  masked_req;
    logic [NUM_REQS-1:0]  masked_grant;
    logic [NUM_REQS-1:0]  unmasked_grant;
    logic [NUM_REQS-1:0]  comb_grant;
    logic [PTR_WIDTH-1:0] comb_grant_idx;

    // --------------------------------------------------------------------------
    // Combinational Two-Tier Priority Logic
    // --------------------------------------------------------------------------
    always_comb begin
        // Generate mask: 1s from priority_ptr up to NUM_REQS-1
        for (int i = 0; i < int'(NUM_REQS); i++) begin
            mask[i] = (PTR_WIDTH'(i) >= priority_ptr);
        end

        masked_req = req & mask;

        // Tier 1: Isolate lowest set bit in masked requests
        masked_grant   = masked_req & (~masked_req + 1'b1);
        // Tier 2: Isolate lowest set bit in unmasked requests (wraparound)
        unmasked_grant = req & (~req + 1'b1);

        // Select tier 1 if any masked request is active, otherwise wrap around
        if (|masked_req) begin
            comb_grant = masked_grant;
        end else begin
            comb_grant = unmasked_grant;
        end

        grant       = comb_grant;
        grant_valid = |comb_grant;

        // Determine integer index of winning grant
        comb_grant_idx = '0;
        for (int i = 0; i < int'(NUM_REQS); i++) begin
            if (comb_grant[i]) begin
                comb_grant_idx = PTR_WIDTH'(i);
            end
        end
        grant_idx = comb_grant_idx;
    end

    // --------------------------------------------------------------------------
    // Sequential Priority Pointer Update
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            priority_ptr <= '0;
        end else if (update_enable && grant_valid) begin
            // Next priority begins immediately above current winner
            if (comb_grant_idx == PTR_WIDTH'(NUM_REQS - 1)) begin
                priority_ptr <= '0;
            end else begin
                priority_ptr <= comb_grant_idx + 1'b1;
            end
        end
    end

    // --------------------------------------------------------------------------
    // Simulation Invariant Checks
    // --------------------------------------------------------------------------
    `ifndef SYNTHESIS
    always_comb begin
        if (grant_valid) begin
            // Assert: At most one grant is active
            assert ($onehot(grant)) else
                $error("[round_robin_arbiter] Invariant violation: grant is not one-hot! grant=%b", grant);
            // Assert: Only an active requester can be granted
            assert ((grant & req) == grant) else
                $error("[round_robin_arbiter] Invariant violation: grant to non-requesting input! grant=%b, req=%b", grant, req);
        end else begin
            // Assert: If no grant, then no requests were present
            assert (req == {NUM_REQS{1'b0}}) else
                $error("[round_robin_arbiter] Invariant violation: requests active but no grant produced! req=%b", req);
        end
    end
    `endif

endmodule

`default_nettype wire
