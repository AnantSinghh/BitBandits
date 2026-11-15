// =============================================================================
// Module Name: tag_ram
// Designer:    Sankalp (Cache Storage & Address Decoding Specialist)
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Synchronous-write, combinational-read cache tag memory array:
//              - 64 Cache entries (NUM_LINES = 64)
//              - 22-bit tag per line (TAG_WIDTH = 22)
//              - 6-bit index addressing (INDEX_WIDTH = 6)
//              - Synchronous write gated by independent write_enable on posedge clk
//              - Combinational (asynchronous) read for single-cycle LOOKUP tag matching
//              - Parameterized dimensions
//              - No reset on tag array (RAM inference friendly, relies on valid_bit_ram)
// =============================================================================

`timescale 1ns / 1ps

module tag_ram #(
    parameter NUM_LINES   = 64,
    parameter INDEX_WIDTH = 6,
    parameter TAG_WIDTH   = 22
)(
    input  wire                   clk,
    input  wire [INDEX_WIDTH-1:0] index,
    input  wire                   write_enable,
    input  wire [TAG_WIDTH-1:0]   write_tag,
    output wire [TAG_WIDTH-1:0]   read_tag
);

    // =========================================================================
    // Storage Array Definition: 64 entries of 22-bit tags
    // =========================================================================
    reg [TAG_WIDTH-1:0] tag_mem [0:NUM_LINES-1];

    // =========================================================================
    // Combinational Read (Asynchronous Read Port)
    // =========================================================================
    // The stored tag is immediately read out based on index and fed directly to
    // the tag comparator during the LOOKUP state for single-cycle hit/miss eval.
    // =========================================================================
    assign read_tag = tag_mem[index];

    // =========================================================================
    // Synchronous Write Process
    // =========================================================================
    // Tag is updated on posedge clk when write_enable is asserted during REFILL.
    // Memory array is not reset to avoid synthesis into 1,408 flip-flops with resets.
    // =========================================================================
    always @(posedge clk) begin
        if (write_enable) begin
            tag_mem[index] <= write_tag;
        end
    end

endmodule
