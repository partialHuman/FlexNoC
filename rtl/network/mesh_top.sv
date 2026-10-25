// ==============================================================================
// File: mesh_top.sv
// Project: FlexNoC - Configurable Network-on-Chip
// Description: Fully parameterizable 2D Mesh Top-Level interconnect.
//              Generates a grid of MESH_WIDTH x MESH_HEIGHT routers with complete
//              East-West, North-South inter-router connectivity and safe boundary
//              tie-offs.
// ==============================================================================

`timescale 1ns/1ps
`default_nettype none

module mesh_top #(
    parameter int unsigned DATA_WIDTH  = 32,
    parameter int unsigned X_WIDTH     = 2,
    parameter int unsigned Y_WIDTH     = 2,
    parameter int unsigned FIFO_DEPTH  = 4,
    parameter int unsigned MESH_WIDTH  = 2,
    parameter int unsigned MESH_HEIGHT = 2
)(
    input  wire clk,
    input  wire rst_n,

    // --------------------------------------------------------------------------
    // Flattened Local Endpoint Interfaces (1 per node)
    // Node index = (y * MESH_WIDTH) + x
    // --------------------------------------------------------------------------
    // Injection (Endpoint -> Router Local Ingress)
    input  wire [(MESH_WIDTH*MESH_HEIGHT*DATA_WIDTH)-1:0] in_local_data,
    input  wire [(MESH_WIDTH*MESH_HEIGHT)-1:0]            in_local_valid,
    output wire [(MESH_WIDTH*MESH_HEIGHT)-1:0]            in_local_ready,

    // Ejection (Router Local Egress -> Endpoint)
    output wire [(MESH_WIDTH*MESH_HEIGHT*DATA_WIDTH)-1:0] out_local_data,
    output wire [(MESH_WIDTH*MESH_HEIGHT)-1:0]            out_local_valid,
    input  wire [(MESH_WIDTH*MESH_HEIGHT)-1:0]            out_local_ready,

    // Diagnostics: OR-reduced error flags from all routers
    output wire [(MESH_WIDTH*MESH_HEIGHT)-1:0]            status_err
);

    // --------------------------------------------------------------------------
    // Inter-Router Wiring Grids
    // --------------------------------------------------------------------------
    // East-West Links:
    // ew_data[y][x]: Carries flits from Router (x, y) East to Router (x+1, y) West
    // we_data[y][x]: Carries flits from Router (x+1, y) West to Router (x, y) East
    wire [DATA_WIDTH-1:0] ew_data  [0:MESH_HEIGHT-1][0:MESH_WIDTH-2];
    wire                  ew_valid [0:MESH_HEIGHT-1][0:MESH_WIDTH-2];
    wire                  ew_ready [0:MESH_HEIGHT-1][0:MESH_WIDTH-2];

    wire [DATA_WIDTH-1:0] we_data  [0:MESH_HEIGHT-1][0:MESH_WIDTH-2];
    wire                  we_valid [0:MESH_HEIGHT-1][0:MESH_WIDTH-2];
    wire                  we_ready [0:MESH_HEIGHT-1][0:MESH_WIDTH-2];

    // North-South Links:
    // sn_data[y][x]: Carries flits from Router (x, y) South to Router (x, y+1) North
    // ns_data[y][x]: Carries flits from Router (x, y+1) North to Router (x, y) South
    wire [DATA_WIDTH-1:0] sn_data  [0:MESH_HEIGHT-2][0:MESH_WIDTH-1];
    wire                  sn_valid [0:MESH_HEIGHT-2][0:MESH_WIDTH-1];
    wire                  sn_ready [0:MESH_HEIGHT-2][0:MESH_WIDTH-1];

    wire [DATA_WIDTH-1:0] ns_data  [0:MESH_HEIGHT-2][0:MESH_WIDTH-1];
    wire                  ns_valid [0:MESH_HEIGHT-2][0:MESH_WIDTH-1];
    wire                  ns_ready [0:MESH_HEIGHT-2][0:MESH_WIDTH-1];

    // --------------------------------------------------------------------------
    // 2D Router Generation Grid
    // --------------------------------------------------------------------------
    generate
        for (genvar y = 0; y < int'(MESH_HEIGHT); y++) begin : gen_row
            for (genvar x = 0; x < int'(MESH_WIDTH); x++) begin : gen_col
                localparam int unsigned NODE_ID = (y * MESH_WIDTH) + x;

                /* verilator lint_off UNUSEDSIGNAL */
                // Wires for this specific router
                wire [DATA_WIDTH-1:0] r_in_north_data,  r_out_north_data;
                wire                  r_in_north_valid, r_out_north_valid;
                wire                  r_in_north_ready, r_out_north_ready;

                wire [DATA_WIDTH-1:0] r_in_south_data,  r_out_south_data;
                wire                  r_in_south_valid, r_out_south_valid;
                wire                  r_in_south_ready, r_out_south_ready;

                wire [DATA_WIDTH-1:0] r_in_east_data,   r_out_east_data;
                wire                  r_in_east_valid,  r_out_east_valid;
                wire                  r_in_east_ready,  r_out_east_ready;

                wire [DATA_WIDTH-1:0] r_in_west_data,   r_out_west_data;
                wire                  r_in_west_valid,  r_out_west_valid;
                wire                  r_in_west_ready,  r_out_west_ready;

                wire [4:0]            r_status_err;
                wire [4:0]            r_status_fifo_full;
                wire [4:0]            r_status_fifo_empty;
                /* verilator lint_on UNUSEDSIGNAL */

                assign status_err[NODE_ID] = |r_status_err;

                // --------------------------------------------------------------
                // North Port Connectivity
                // --------------------------------------------------------------
                if (y == 0) begin : gen_north_boundary
                    // Top boundary: No upward neighbor
                    assign r_in_north_data  = '0;
                    assign r_in_north_valid = 1'b0;
                    assign r_out_north_ready = 1'b0;
                end else begin : gen_north_internal
                    // Connect to Router (x, y-1) South
                    assign r_in_north_data      = sn_data[y-1][x];
                    assign r_in_north_valid     = sn_valid[y-1][x];
                    assign sn_ready[y-1][x]     = r_in_north_ready;

                    assign ns_data[y-1][x]      = r_out_north_data;
                    assign ns_valid[y-1][x]     = r_out_north_valid;
                    assign r_out_north_ready    = ns_ready[y-1][x];
                end

                // --------------------------------------------------------------
                // South Port Connectivity
                // --------------------------------------------------------------
                if (y == MESH_HEIGHT - 1) begin : gen_south_boundary
                    // Bottom boundary: No downward neighbor
                    assign r_in_south_data   = '0;
                    assign r_in_south_valid  = 1'b0;
                    assign r_out_south_ready = 1'b0;
                end else begin : gen_south_internal
                    // Connect to Router (x, y+1) North
                    assign sn_data[y][x]        = r_out_south_data;
                    assign sn_valid[y][x]       = r_out_south_valid;
                    assign r_out_south_ready    = sn_ready[y][x];

                    assign r_in_south_data      = ns_data[y][x];
                    assign r_in_south_valid     = ns_valid[y][x];
                    assign ns_ready[y][x]       = r_in_south_ready;
                end

                // --------------------------------------------------------------
                // West Port Connectivity
                // --------------------------------------------------------------
                if (x == 0) begin : gen_west_boundary
                    // Left boundary: No westward neighbor
                    assign r_in_west_data   = '0;
                    assign r_in_west_valid  = 1'b0;
                    assign r_out_west_ready = 1'b0;
                end else begin : gen_west_internal
                    // Connect to Router (x-1, y) East
                    assign r_in_west_data       = ew_data[y][x-1];
                    assign r_in_west_valid      = ew_valid[y][x-1];
                    assign ew_ready[y][x-1]     = r_in_west_ready;

                    assign we_data[y][x-1]      = r_out_west_data;
                    assign we_valid[y][x-1]     = r_out_west_valid;
                    assign r_out_west_ready     = we_ready[y][x-1];
                end

                // --------------------------------------------------------------
                // East Port Connectivity
                // --------------------------------------------------------------
                if (x == MESH_WIDTH - 1) begin : gen_east_boundary
                    // Right boundary: No eastward neighbor
                    assign r_in_east_data   = '0;
                    assign r_in_east_valid  = 1'b0;
                    assign r_out_east_ready = 1'b0;
                end else begin : gen_east_internal
                    // Connect to Router (x+1, y) West
                    assign ew_data[y][x]        = r_out_east_data;
                    assign ew_valid[y][x]       = r_out_east_valid;
                    assign r_out_east_ready     = ew_ready[y][x];

                    assign r_in_east_data       = we_data[y][x];
                    assign r_in_east_valid      = we_valid[y][x];
                    assign we_ready[y][x]       = r_in_east_ready;
                end

                // --------------------------------------------------------------
                // Local Router Instance
                // --------------------------------------------------------------
                flexnoc_router #(
                    .DATA_WIDTH (DATA_WIDTH),
                    .X_WIDTH    (X_WIDTH),
                    .Y_WIDTH    (Y_WIDTH),
                    .FIFO_DEPTH (FIFO_DEPTH),
                    .ROUTER_X   (x),
                    .ROUTER_Y   (y),
                    .MESH_WIDTH (MESH_WIDTH),
                    .MESH_HEIGHT(MESH_HEIGHT)
                ) u_router (
                    .clk   (clk),
                    .rst_n (rst_n),

                    // Local
                    .in_local_data  (in_local_data[(NODE_ID*DATA_WIDTH) +: DATA_WIDTH]),
                    .in_local_valid (in_local_valid[NODE_ID]),
                    .in_local_ready (in_local_ready[NODE_ID]),

                    .out_local_data (out_local_data[(NODE_ID*DATA_WIDTH) +: DATA_WIDTH]),
                    .out_local_valid(out_local_valid[NODE_ID]),
                    .out_local_ready(out_local_ready[NODE_ID]),

                    // North
                    .in_north_data  (r_in_north_data),
                    .in_north_valid (r_in_north_valid),
                    .in_north_ready (r_in_north_ready),

                    .out_north_data (r_out_north_data),
                    .out_north_valid(r_out_north_valid),
                    .out_north_ready(r_out_north_ready),

                    // East
                    .in_east_data   (r_in_east_data),
                    .in_east_valid  (r_in_east_valid),
                    .in_east_ready  (r_in_east_ready),

                    .out_east_data  (r_out_east_data),
                    .out_east_valid (r_out_east_valid),
                    .out_east_ready (r_out_east_ready),

                    // South
                    .in_south_data  (r_in_south_data),
                    .in_south_valid (r_in_south_valid),
                    .in_south_ready (r_in_south_ready),

                    .out_south_data (r_out_south_data),
                    .out_south_valid(r_out_south_valid),
                    .out_south_ready(r_out_south_ready),

                    // West
                    .in_west_data   (r_in_west_data),
                    .in_west_valid  (r_in_west_valid),
                    .in_west_ready  (r_in_west_ready),

                    .out_west_data  (r_out_west_data),
                    .out_west_valid (r_out_west_valid),
                    .out_west_ready (r_out_west_ready),

                    // Diagnostics
                    .status_fifo_full (r_status_fifo_full),
                    .status_fifo_empty(r_status_fifo_empty),
                    .status_route_err (r_status_err)
                );

            end
        end
    endgenerate

endmodule

`default_nettype wire
