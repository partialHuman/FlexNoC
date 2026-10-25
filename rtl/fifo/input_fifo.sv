// ==============================================================================
// File: input_fifo.sv
// Project: FlexNoC - Configurable Network-on-Chip
// Description: Synchronous First-Word Fall-Through (FWFT) FIFO with independent
//              registered-ready flow control, supporting simultaneous push and pop.
//              Guarantees combinational isolation: push_ready never combinationally
//              depends on pop_ready.
// ==============================================================================

`timescale 1ns/1ps
`default_nettype none

module input_fifo #(
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned DEPTH      = 4
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Ingress (Push) Interface
    input  wire [DATA_WIDTH-1:0]  push_data,
    input  wire                   push_valid,
    output wire                   push_ready,

    // Egress (Pop) Interface
    output wire [DATA_WIDTH-1:0]  pop_data,
    output wire                   pop_valid,
    input  wire                   pop_ready,

    // Status Flags
    output wire                   empty,
    output wire                   full,
    output wire [$clog2(DEPTH+1)-1:0] count
);

    // --------------------------------------------------------------------------
    // Compile-time Parameter Validation
    // --------------------------------------------------------------------------
    initial begin
        if (DEPTH < 2) begin
            $fatal(1, "[input_fifo] DEPTH must be at least 2. Provided DEPTH = %0d", DEPTH);
        end
        if (DATA_WIDTH < 1) begin
            $fatal(1, "[input_fifo] DATA_WIDTH must be at least 1. Provided DATA_WIDTH = %0d", DATA_WIDTH);
        end
    end

    // --------------------------------------------------------------------------
    // Local Types and Registers
    // --------------------------------------------------------------------------
    localparam int unsigned ADDR_WIDTH  = (DEPTH > 1) ? $clog2(DEPTH) : 1;
    localparam int unsigned COUNT_WIDTH = $clog2(DEPTH + 1);

    logic [DATA_WIDTH-1:0]  mem [0:DEPTH-1];
    logic [ADDR_WIDTH-1:0]  wr_ptr;
    logic [ADDR_WIDTH-1:0]  rd_ptr;
    logic [COUNT_WIDTH-1:0] fifo_count;

    // Handshake conditions
    wire push_fire = push_valid && push_ready;
    wire pop_fire  = pop_valid  && pop_ready;

    // Status assignments
    // Combinational isolation: push_ready strictly reflects registered buffer availability
    assign empty      = (fifo_count == {COUNT_WIDTH{1'b0}});
    assign full       = (fifo_count == COUNT_WIDTH'(DEPTH));
    assign push_ready = !full;
    assign pop_valid  = !empty;
    assign count      = fifo_count;

    // FWFT read: Data at head of FIFO is continuously presented
    assign pop_data   = mem[rd_ptr];

    // --------------------------------------------------------------------------
    // Sequential State and Storage Update
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= {ADDR_WIDTH{1'b0}};
            rd_ptr     <= {ADDR_WIDTH{1'b0}};
            fifo_count <= {COUNT_WIDTH{1'b0}};
        end else begin
            // Memory write on valid push
            if (push_fire) begin
                mem[wr_ptr] <= push_data;
                if (wr_ptr == ADDR_WIDTH'(DEPTH - 1)) begin
                    wr_ptr <= {ADDR_WIDTH{1'b0}};
                end else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end

            // Read pointer update on valid pop
            if (pop_fire) begin
                if (rd_ptr == ADDR_WIDTH'(DEPTH - 1)) begin
                    rd_ptr <= {ADDR_WIDTH{1'b0}};
                end else begin
                    rd_ptr <= rd_ptr + 1'b1;
                end
            end

            // Occupancy counter update
            case ({push_fire, pop_fire})
                2'b10: begin // Push only
                    fifo_count <= fifo_count + 1'b1;
                end
                2'b01: begin // Pop only
                    fifo_count <= fifo_count - 1'b1;
                end
                2'b11: begin // Simultaneous push and pop
                    fifo_count <= fifo_count; // unchanged
                end
                default: begin // Idle (2'b00)
                    fifo_count <= fifo_count;
                end
            endcase
        end
    end

    // --------------------------------------------------------------------------
    // Assertions and Invariant Checks (Simulation Verification)
    // --------------------------------------------------------------------------
    `ifndef SYNTHESIS
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset state
        end else begin
            // Check: No overflow
            if (full && push_valid && !pop_fire) begin
                assert (!push_fire) else
                    $error("[input_fifo] Invariant violation: FIFO overflow occurred!");
            end
            // Check: No underflow
            if (empty && pop_ready) begin
                assert (!pop_fire) else
                    $error("[input_fifo] Invariant violation: FIFO underflow occurred!");
            end
            // Check: Count bounds
            assert (fifo_count <= COUNT_WIDTH'(DEPTH)) else
                $error("[input_fifo] Invariant violation: fifo_count exceeded DEPTH: %0d > %0d", 
                       fifo_count, DEPTH);
        end
    end
    `endif

endmodule

`default_nettype wire
