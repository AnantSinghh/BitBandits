// =============================================================================
// Module Name: address_decoder
// Designer:    Sankalp
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Decodes a 32-bit CPU memory address into cache fields:
//              - Tag:          address[31:10] (22 bits)
//              - Index:        address[9:4]   (6 bits -> 64 lines)
//              - Block Offset: address[3:0]   (4 bits -> 16 bytes)
//              - Word Select:  address[3:2]   (2 bits -> 4 words)
//              - Byte Offset:  address[1:0]   (2 bits)
//              Also outputs a 16-byte block-aligned address for memory refills.
// =============================================================================

`timescale 1ns / 1ps

module address_decoder (
    input  wire [31:0] addr,
    output wire [21:0] tag,
    output wire [5:0]  index,
    output wire [3:0]  block_offset,
    output wire [1:0]  word_sel,
    output wire [1:0]  byte_offset,
    output wire [31:0] block_addr
);

    // Tag field: 22 bits
    assign tag          = addr[31:10];

    // Cache line index: 6 bits (64 sets/lines)
    assign index        = addr[9:4];

    // Block offset within 16-byte line: 4 bits
    assign block_offset = addr[3:0];

    // Word selection within block: 2 bits (4 words, 32-bit each)
    assign word_sel     = addr[3:2];

    // Byte selection within word: 2 bits
    assign byte_offset  = addr[1:0];

    // Block-aligned address (lower 4 bits zeroed)
    assign block_addr   = {addr[31:4], 4'b0000};

endmodule
