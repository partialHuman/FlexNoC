// ==============================================================================
// File: flexnoc_pkg.sv
// Project: FlexNoC - Configurable Network-on-Chip
// Description: Global package defining parameters, enumerations, structures,
//              and helper utility functions for FlexNoC routers and mesh.
// ==============================================================================

`timescale 1ns/1ps

`ifndef FLEXNOC_PKG_SV
`define FLEXNOC_PKG_SV

/* verilator lint_off UNUSEDPARAM */
/* verilator lint_off UNUSEDSIGNAL */
package flexnoc_pkg;

    // --------------------------------------------------------------------------
    // Default Global Parameters
    // --------------------------------------------------------------------------
    localparam int unsigned DEFAULT_FLIT_WIDTH    = 32;
    localparam int unsigned DEFAULT_X_WIDTH       = 2;
    localparam int unsigned DEFAULT_Y_WIDTH       = 2;
    localparam int unsigned DEFAULT_PKT_ID_WIDTH  = 8;
    localparam int unsigned DEFAULT_PAYLOAD_WIDTH = DEFAULT_FLIT_WIDTH 
                                                  - (2 * DEFAULT_X_WIDTH) 
                                                  - (2 * DEFAULT_Y_WIDTH) 
                                                  - DEFAULT_PKT_ID_WIDTH; // 16 bits
    localparam int unsigned DEFAULT_FIFO_DEPTH    = 4;

    // --------------------------------------------------------------------------
    // Router Port Identifiers
    // --------------------------------------------------------------------------
    localparam int unsigned NUM_PORTS = 5;

    typedef enum logic [2:0] {
        PORT_LOCAL = 3'd0,
        PORT_NORTH = 3'd1,
        PORT_EAST  = 3'd2,
        PORT_SOUTH = 3'd3,
        PORT_WEST  = 3'd4
    } port_id_e;

    // Helper function for packet construction in testbenches / RTL
    function automatic logic [DEFAULT_FLIT_WIDTH-1:0] create_flit(
        input logic [DEFAULT_X_WIDTH-1:0]       dx,
        input logic [DEFAULT_Y_WIDTH-1:0]       dy,
        input logic [DEFAULT_X_WIDTH-1:0]       sx,
        input logic [DEFAULT_Y_WIDTH-1:0]       sy,
        input logic [DEFAULT_PKT_ID_WIDTH-1:0]  id,
        input logic [DEFAULT_PAYLOAD_WIDTH-1:0] pld
    );
        create_flit = {dx, dy, sx, sy, id, pld};
    endfunction

    function automatic logic [DEFAULT_PAYLOAD_WIDTH-1:0] get_payload(
        input logic [DEFAULT_FLIT_WIDTH-1:0] flit
    );
        get_payload = flit[DEFAULT_PAYLOAD_WIDTH-1:0];
    endfunction

endpackage : flexnoc_pkg
/* verilator lint_on UNUSEDPARAM */
/* verilator lint_on UNUSEDSIGNAL */

`endif // FLEXNOC_PKG_SV
