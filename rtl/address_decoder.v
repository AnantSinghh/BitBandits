// =============================================================================
// Module Name: address_decoder
// Designer:    Sankalp (Cache Storage & Address Decoding Specialist)
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Fully parameterized address decoder module that unpacks a 32-bit
//              flat CPU byte address into direct-mapped cache architectural fields:
//              - Tag:          address[31:10] (22 bits) -> cache line tag match
//              - Index:        address[9:4]   (6 bits)  -> 64 cache lines/sets
//              - Block Offset: address[3:0]   (4 bits)  -> 16-byte line offset
//              - Word Select:  address[3:2]   (2 bits)  -> 4 words (32-bit each)
//              - Byte Offset:  address[1:0]   (2 bits)  -> 4 bytes within word
//              - Block Addr:   {addr[31:4], 4'b0000}    -> 16-byte aligned base
// =============================================================================

`timescale 1ns / 1ps

module address_decoder #(
    parameter ADDR_WIDTH        = 32,
    parameter TAG_WIDTH         = 22,
    parameter INDEX_WIDTH       = 6,
    parameter OFFSET_WIDTH      = 4,
    parameter WORD_SEL_WIDTH    = 2,
    parameter BYTE_OFFSET_WIDTH = 2
)(
    input  wire [ADDR_WIDTH-1:0]        addr,
    output wire [TAG_WIDTH-1:0]         tag,
    output wire [INDEX_WIDTH-1:0]       index,
    output wire [OFFSET_WIDTH-1:0]      block_offset,
    output wire [WORD_SEL_WIDTH-1:0]    word_sel,
    output wire [BYTE_OFFSET_WIDTH-1:0] byte_offset,
    output wire [ADDR_WIDTH-1:0]        block_addr
);

    // =========================================================================
    // Parameter Validation / Architectural Sanity Check
    // =========================================================================
    // In a standard byte-addressable direct-mapped cache:
    // ADDR_WIDTH == TAG_WIDTH + INDEX_WIDTH + OFFSET_WIDTH
    // OFFSET_WIDTH == WORD_SEL_WIDTH + BYTE_OFFSET_WIDTH
    // =========================================================================

    // 1. Tag field extraction: [31:10] (22 bits)
    // Identifies whether the cached block corresponds to the requested memory frame
    assign tag = addr[ADDR_WIDTH-1 : ADDR_WIDTH - TAG_WIDTH];

    // 2. Index field extraction: [9:4] (6 bits)
    // Directly indexes into one of the 64 cache lines (2^6 = 64)
    assign index = addr[OFFSET_WIDTH + INDEX_WIDTH - 1 : OFFSET_WIDTH];

    // 3. Full Block Offset: [3:0] (4 bits)
    // Byte offset within a 16-byte block (2^4 = 16 bytes)
    assign block_offset = addr[OFFSET_WIDTH-1 : 0];

    // 4. Word Select: [3:2] (2 bits)
    // Selects one of the four 32-bit words within the 128-bit cache line
    assign word_sel = addr[OFFSET_WIDTH-1 : OFFSET_WIDTH - WORD_SEL_WIDTH];

    // 5. Byte Offset: [1:0] (2 bits)
    // Identifies byte within a 32-bit word (for sub-word access)
    assign byte_offset = addr[BYTE_OFFSET_WIDTH-1 : 0];

    // 6. Block-Aligned Address: {addr[31:4], 4'b0000}
    // Masks out block offset bits to drive main memory refill requests
    assign block_addr = {addr[ADDR_WIDTH-1 : OFFSET_WIDTH], {OFFSET_WIDTH{1'b0}}};

endmodule
