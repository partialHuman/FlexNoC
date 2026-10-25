// ==============================================================================
// File: flexnoc_router.sv
// Project: FlexNoC - Configurable Network-on-Chip
// Description: Fully integrated 5-port input-queued router with dimension-order
//              XY routing, per-output round-robin arbitration, and non-blocking
//              crossbar switching.
// ==============================================================================

`timescale 1ns/1ps
`default_nettype none

module flexnoc_router #(
    parameter int unsigned DATA_WIDTH  = 32,
    parameter int unsigned X_WIDTH     = 2,
    parameter int unsigned Y_WIDTH     = 2,
    parameter int unsigned FIFO_DEPTH  = 4,
    parameter int unsigned ROUTER_X    = 0,
    parameter int unsigned ROUTER_Y    = 0,
    parameter int unsigned MESH_WIDTH  = 4,
    parameter int unsigned MESH_HEIGHT = 4
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // --------------------------------------------------------------------------
    // 5 Ingress Ports (Local, North, East, South, West)
    // --------------------------------------------------------------------------
    // Local Ingress
    input  wire [DATA_WIDTH-1:0]   in_local_data,
    input  wire                    in_local_valid,
    output wire                    in_local_ready,

    // North Ingress
    input  wire [DATA_WIDTH-1:0]   in_north_data,
    input  wire                    in_north_valid,
    output wire                    in_north_ready,

    // East Ingress
    input  wire [DATA_WIDTH-1:0]   in_east_data,
    input  wire                    in_east_valid,
    output wire                    in_east_ready,

    // South Ingress
    input  wire [DATA_WIDTH-1:0]   in_south_data,
    input  wire                    in_south_valid,
    output wire                    in_south_ready,

    // West Ingress
    input  wire [DATA_WIDTH-1:0]   in_west_data,
    input  wire                    in_west_valid,
    output wire                    in_west_ready,

    // --------------------------------------------------------------------------
    // 5 Egress Ports (Local, North, East, South, West)
    // --------------------------------------------------------------------------
    // Local Egress
    output wire [DATA_WIDTH-1:0]   out_local_data,
    output wire                    out_local_valid,
    input  wire                    out_local_ready,

    // North Egress
    output wire [DATA_WIDTH-1:0]   out_north_data,
    output wire                    out_north_valid,
    input  wire                    out_north_ready,

    // East Egress
    output wire [DATA_WIDTH-1:0]   out_east_data,
    output wire                    out_east_valid,
    input  wire                    out_east_ready,

    // South Egress
    output wire [DATA_WIDTH-1:0]   out_south_data,
    output wire                    out_south_valid,
    input  wire                    out_south_ready,

    // West Egress
    output wire [DATA_WIDTH-1:0]   out_west_data,
    output wire                    out_west_valid,
    input  wire                    out_west_ready,

    // --------------------------------------------------------------------------
    // Router Diagnostic Status
    // --------------------------------------------------------------------------
    output wire [4:0]              status_fifo_full,
    output wire [4:0]              status_fifo_empty,
    output wire [4:0]              status_route_err
);

    // --------------------------------------------------------------------------
    // Internal Array Signal Packing
    // --------------------------------------------------------------------------
    // Port order: 0:Local, 1:North, 2:East, 3:South, 4:West
    wire [DATA_WIDTH-1:0] in_data_arr  [0:4];
    wire                  in_valid_arr [0:4];
    wire                  in_ready_arr [0:4];

    wire [DATA_WIDTH-1:0] out_data_arr  [0:4];
    wire                  out_valid_arr [0:4];
    wire                  out_ready_arr [0:4];

    // Ingress bindings
    assign in_data_arr[flexnoc_pkg::PORT_LOCAL] = in_local_data;
    assign in_valid_arr[flexnoc_pkg::PORT_LOCAL] = in_local_valid;
    assign in_local_ready           = in_ready_arr[flexnoc_pkg::PORT_LOCAL];

    assign in_data_arr[flexnoc_pkg::PORT_NORTH] = in_north_data;
    assign in_valid_arr[flexnoc_pkg::PORT_NORTH] = in_north_valid;
    assign in_north_ready           = in_ready_arr[flexnoc_pkg::PORT_NORTH];

    assign in_data_arr[flexnoc_pkg::PORT_EAST]  = in_east_data;
    assign in_valid_arr[flexnoc_pkg::PORT_EAST]  = in_east_valid;
    assign in_east_ready            = in_ready_arr[flexnoc_pkg::PORT_EAST];

    assign in_data_arr[flexnoc_pkg::PORT_SOUTH] = in_south_data;
    assign in_valid_arr[flexnoc_pkg::PORT_SOUTH] = in_south_valid;
    assign in_south_ready           = in_ready_arr[flexnoc_pkg::PORT_SOUTH];

    assign in_data_arr[flexnoc_pkg::PORT_WEST]  = in_west_data;
    assign in_valid_arr[flexnoc_pkg::PORT_WEST]  = in_west_valid;
    assign in_west_ready            = in_ready_arr[flexnoc_pkg::PORT_WEST];

    // Egress bindings
    assign out_local_data          = out_data_arr[flexnoc_pkg::PORT_LOCAL];
    assign out_local_valid         = out_valid_arr[flexnoc_pkg::PORT_LOCAL];
    assign out_ready_arr[flexnoc_pkg::PORT_LOCAL] = out_local_ready;

    assign out_north_data          = out_data_arr[flexnoc_pkg::PORT_NORTH];
    assign out_north_valid         = out_valid_arr[flexnoc_pkg::PORT_NORTH];
    assign out_ready_arr[flexnoc_pkg::PORT_NORTH] = out_north_ready;

    assign out_east_data           = out_data_arr[flexnoc_pkg::PORT_EAST];
    assign out_east_valid          = out_valid_arr[flexnoc_pkg::PORT_EAST];
    assign out_ready_arr[flexnoc_pkg::PORT_EAST]  = out_east_ready;

    assign out_south_data          = out_data_arr[flexnoc_pkg::PORT_SOUTH];
    assign out_south_valid         = out_valid_arr[flexnoc_pkg::PORT_SOUTH];
    assign out_ready_arr[flexnoc_pkg::PORT_SOUTH] = out_south_ready;

    assign out_west_data           = out_data_arr[flexnoc_pkg::PORT_WEST];
    assign out_west_valid          = out_valid_arr[flexnoc_pkg::PORT_WEST];
    assign out_ready_arr[flexnoc_pkg::PORT_WEST]  = out_west_ready;

    // --------------------------------------------------------------------------
    // Ingress FIFOs
    // --------------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] fifo_data  [0:4];
    wire                  fifo_valid [0:4];
    logic                 fifo_ready [0:4];
    wire                  fifo_empty [0:4];
    wire                  fifo_full  [0:4];
    /* verilator lint_off UNUSEDSIGNAL */
    wire [$clog2(FIFO_DEPTH+1)-1:0] fifo_count_unused [0:4];
    /* verilator lint_on UNUSEDSIGNAL */

    assign status_fifo_full  = {fifo_full[4],  fifo_full[3],  fifo_full[2],  fifo_full[1],  fifo_full[0]};
    assign status_fifo_empty = {fifo_empty[4], fifo_empty[3], fifo_empty[2], fifo_empty[1], fifo_empty[0]};

    generate
        for (genvar i = 0; i < 5; i++) begin : gen_input_fifos
            input_fifo #(
                .DATA_WIDTH(DATA_WIDTH),
                .DEPTH(FIFO_DEPTH)
            ) u_input_fifo (
                .clk       (clk),
                .rst_n     (rst_n),
                .push_data (in_data_arr[i]),
                .push_valid(in_valid_arr[i]),
                .push_ready(in_ready_arr[i]),
                .pop_data  (fifo_data[i]),
                .pop_valid (fifo_valid[i]),
                .pop_ready (fifo_ready[i]),
                .empty     (fifo_empty[i]),
                .full      (fifo_full[i]),
                .count     (fifo_count_unused[i])
            );
        end
    endgenerate

    // --------------------------------------------------------------------------
    // Route Computation Units (5x)
    // --------------------------------------------------------------------------
    wire [4:0] rc_req [0:4];
    wire       rc_err [0:4];

    assign status_route_err = {rc_err[4], rc_err[3], rc_err[2], rc_err[1], rc_err[0]};

    generate
        for (genvar i = 0; i < 5; i++) begin : gen_route_compute
            // Extract destination coordinates using parameterized bit slice
            wire [X_WIDTH-1:0] dest_x = fifo_data[i][DATA_WIDTH-1 -: X_WIDTH];
            wire [Y_WIDTH-1:0] dest_y = fifo_data[i][DATA_WIDTH-1-X_WIDTH -: Y_WIDTH];

            route_compute #(
                .X_WIDTH    (X_WIDTH),
                .Y_WIDTH    (Y_WIDTH),
                .MESH_WIDTH (MESH_WIDTH),
                .MESH_HEIGHT(MESH_HEIGHT)
            ) u_route_compute (
                .curr_x   (X_WIDTH'(ROUTER_X)),
                .curr_y   (Y_WIDTH'(ROUTER_Y)),
                .dest_x   (dest_x),
                .dest_y   (dest_y),
                .pkt_valid(fifo_valid[i]),
                .route_req(rc_req[i]),
                .route_err(rc_err[i])
            );
        end
    endgenerate

    // --------------------------------------------------------------------------
    // Request Matrix Generation & Round-Robin Arbiters (5x)
    // --------------------------------------------------------------------------
    // arb_req[o][i] is asserted when ingress FIFO i requests egress port o
    logic [4:0] arb_req [0:4];
    wire  [4:0] arb_grant [0:4];
    wire        arb_grant_valid [0:4];
    /* verilator lint_off UNUSEDSIGNAL */
    wire  [2:0] arb_grant_idx_unused [0:4];
    /* verilator lint_on UNUSEDSIGNAL */

    always_comb begin
        for (int o = 0; o < 5; o++) begin
            for (int i = 0; i < 5; i++) begin
                arb_req[o][i] = fifo_valid[i] && rc_req[i][o];
            end
        end
    end

    generate
        for (genvar o = 0; o < 5; o++) begin : gen_arbiters
            wire update_enable = out_valid_arr[o] && out_ready_arr[o];

            round_robin_arbiter #(
                .NUM_REQS(5)
            ) u_arbiter (
                .clk          (clk),
                .rst_n        (rst_n),
                .req          (arb_req[o]),
                .update_enable(update_enable),
                .grant        (arb_grant[o]),
                .grant_valid  (arb_grant_valid[o]),
                .grant_idx    (arb_grant_idx_unused[o])
            );

            assign out_valid_arr[o] = arb_grant_valid[o];
        end
    endgenerate

    // --------------------------------------------------------------------------
    // Ingress FIFO Pop Control Logic
    // --------------------------------------------------------------------------
    // Ingress FIFO i pops if it won grant on output o AND output o accepted (ready=1)
    always_comb begin
        for (int i = 0; i < 5; i++) begin
            logic pop_cond;
            pop_cond = 1'b0;
            for (int o = 0; o < 5; o++) begin
                if (arb_grant[o][i] && out_ready_arr[o]) begin
                    pop_cond = 1'b1;
                end
            end
            fifo_ready[i] = pop_cond;
        end
    end

    // --------------------------------------------------------------------------
    // Crossbar Switch (5x5)
    // --------------------------------------------------------------------------
    // Flatten arrays for crossbar switch port matching
    wire [(5*DATA_WIDTH)-1:0] xbar_in_data;
    wire [(5*5)-1:0]          xbar_grant_matrix;
    wire [(5*DATA_WIDTH)-1:0] xbar_out_data;

    generate
        for (genvar i = 0; i < 5; i++) begin : gen_xbar_in_pack
            assign xbar_in_data[(i*DATA_WIDTH) +: DATA_WIDTH] = fifo_data[i];
        end
        for (genvar o = 0; o < 5; o++) begin : gen_xbar_grant_pack
            assign xbar_grant_matrix[(o*5) +: 5] = arb_grant[o];
            assign out_data_arr[o] = xbar_out_data[(o*DATA_WIDTH) +: DATA_WIDTH];
        end
    endgenerate

    crossbar_switch #(
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_INPUTS (5),
        .NUM_OUTPUTS(5)
    ) u_crossbar_switch (
        .in_data     (xbar_in_data),
        .grant_matrix(xbar_grant_matrix),
        .out_data    (xbar_out_data)
    );

endmodule

`default_nettype wire
