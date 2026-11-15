// =============================================================================
// Module Name: cache_storage
// Designer:    Sankalp (Cache Storage & Address Decoding Specialist)
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Structural integration of the cache storage subsystem.
//              Connects the three dedicated storage submodules:
//              1. cache_data_ram.v - 64 lines x 128-bit data blocks
//              2. tag_ram.v        - 64 lines x 22-bit address tags
//              3. valid_bit_ram.v  - 64 lines x 1-bit line validity flags
//
// Technical Highlights:
//   - Clean structural modularity adhering to the team interface agreed upon by MANAS.
//   - Combinational read port for zero-latency LOOKUP tag matching and data extraction.
//   - Synchronous write port for atomic cache line refill during REFILL state.
//   - Asymmetric reset: ONLY valid_bit_ram is connected to rst, avoiding 9,600 FFs
//     of unnecessary reset overhead on data and tag RAMs.
//   - Zero latches, zero multiple drivers, pure synthesizable Verilog.
// =============================================================================

`timescale 1ns / 1ps

module cache_storage #(
    parameter NUM_LINES   = 64,
    parameter INDEX_WIDTH = 6,
    parameter TAG_WIDTH   = 22,
    parameter BLOCK_WIDTH = 128
)(
    input  wire                   clk,
    input  wire                   rst,
    
    // Read port (combinational for LOOKUP evaluation)
    input  wire [INDEX_WIDTH-1:0] read_index,
    output wire                   read_valid,
    output wire [TAG_WIDTH-1:0]   read_tag,
    output wire [BLOCK_WIDTH-1:0] read_data,

    // Write / Refill port (synchronous for REFILL commit)
    input  wire                   write_en,
    input  wire [INDEX_WIDTH-1:0] write_index,
    input  wire [TAG_WIDTH-1:0]   write_tag,
    input  wire [BLOCK_WIDTH-1:0] write_data,
    input  wire                   write_valid
);

    // =========================================================================
    // Internal Index Steering
    // =========================================================================
    // When writing (write_en = 1), the storage submodules target write_index.
    // When reading (write_en = 0), the storage submodules access read_index.
    // Note: In Manas's controller FSM, read_index and write_index are both derived
    // from the latched address index during REFILL, so index consistency is guaranteed.
    // =========================================================================
    wire [INDEX_WIDTH-1:0] storage_index = write_en ? write_index : read_index;

    // =========================================================================
    // 1. Cache Data RAM Submodule Instance
    // =========================================================================
    cache_data_ram #(
        .NUM_LINES   (NUM_LINES),
        .INDEX_WIDTH (INDEX_WIDTH),
        .BLOCK_WIDTH (BLOCK_WIDTH)
    ) u_data_ram (
        .clk          (clk),
        .index        (storage_index),
        .write_enable (write_en),
        .write_data   (write_data),
        .read_data    (read_data)
    );

    // =========================================================================
    // 2. Cache Tag RAM Submodule Instance
    // =========================================================================
    tag_ram #(
        .NUM_LINES   (NUM_LINES),
        .INDEX_WIDTH (INDEX_WIDTH),
        .TAG_WIDTH   (TAG_WIDTH)
    ) u_tag_ram (
        .clk          (clk),
        .index        (storage_index),
        .write_enable (write_en),
        .write_tag    (write_tag),
        .read_tag     (read_tag)
    );

    // =========================================================================
    // 3. Cache Valid-Bit RAM Submodule Instance
    // =========================================================================
    // Note: rst is exclusively routed to valid_bit_ram to invalidate all lines
    // on cold power-up or hardware reset.
    // =========================================================================
    valid_bit_ram #(
        .NUM_LINES   (NUM_LINES),
        .INDEX_WIDTH (INDEX_WIDTH)
    ) u_valid_ram (
        .clk          (clk),
        .rst          (rst),
        .index        (storage_index),
        .write_enable (write_en),
        .write_valid  (write_valid),
        .read_valid   (read_valid)
    );

endmodule
