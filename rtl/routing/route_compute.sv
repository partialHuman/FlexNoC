// ==============================================================================
// File: route_compute.sv
// Project: FlexNoC - Configurable Network-on-Chip
// Description: Dimension-order XY route computation unit.
//              Purely combinational logic that compares destination coordinates
//              with current router coordinates and asserts a one-hot request vector.
// ==============================================================================

`timescale 1ns/1ps
`default_nettype none

module route_compute #(
    parameter int unsigned X_WIDTH     = 2,
    parameter int unsigned Y_WIDTH     = 2,
    parameter int unsigned MESH_WIDTH  = 4,
    parameter int unsigned MESH_HEIGHT = 4
)(
    // Current Router Coordinates
    input  wire [X_WIDTH-1:0]  curr_x,
    input  wire [Y_WIDTH-1:0]  curr_y,

    // Incoming Flit Destination Coordinates
    input  wire [X_WIDTH-1:0]  dest_x,
    input  wire [Y_WIDTH-1:0]  dest_y,
    input  wire                pkt_valid,

    // One-hot output route request:
    // [0]: Local, [1]: North, [2]: East, [3]: South, [4]: West
    output logic [4:0]         route_req,
    output logic               route_err
);

    always_comb begin
        route_req = 5'b00000;
        route_err = 1'b0;

        if (pkt_valid) begin
            // Destination bounds validation with explicitly matched bit widths
            if ((32'(dest_x) >= 32'(MESH_WIDTH)) || (32'(dest_y) >= 32'(MESH_HEIGHT))) begin
                route_err = 1'b1;
                // Safe error handling: divert to local port for exception handling
                route_req[flexnoc_pkg::PORT_LOCAL] = 1'b1;
            end
            // Dimension-Order XY Routing:
            // Step 1: Compare X coordinate (East / West)
            else if (dest_x > curr_x) begin
                route_req[flexnoc_pkg::PORT_EAST] = 1'b1;
            end
            else if (dest_x < curr_x) begin
                route_req[flexnoc_pkg::PORT_WEST] = 1'b1;
            end
            // Step 2: Compare Y coordinate (North / South)
            else if (dest_y > curr_y) begin
                route_req[flexnoc_pkg::PORT_SOUTH] = 1'b1;
            end
            else if (dest_y < curr_y) begin
                route_req[flexnoc_pkg::PORT_NORTH] = 1'b1;
            end
            // Step 3: Coordinates match -> Local ejection
            else begin
                route_req[flexnoc_pkg::PORT_LOCAL] = 1'b1;
            end
        end
    end

    // --------------------------------------------------------------------------
    // Simulation Invariant Checks
    // --------------------------------------------------------------------------
    `ifndef SYNTHESIS
    always_comb begin
        if (pkt_valid) begin
            // Assert that route_req is strictly one-hot
            assert ($onehot(route_req)) else
                $error("[route_compute] Invariant violation: route_req is not one-hot! req=%b, curr=(%0d,%0d), dest=(%0d,%0d)",
                       route_req, curr_x, curr_y, dest_x, dest_y);
        end else begin
            // Assert no spurious requests when invalid
            assert (route_req == 5'b00000) else
                $error("[route_compute] Spurious request asserted while pkt_valid=0! req=%b", route_req);
        end
    end
    `endif

endmodule

`default_nettype wire
