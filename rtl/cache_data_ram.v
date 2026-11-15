// =============================================================================
// Module Name: cache_data_ram
// Designer:    Sankalp (Cache Storage & Address Decoding Specialist)
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Synchronous-write, combinational-read cache data memory array:
//              - 64 Cache lines (NUM_LINES = 64)
//              - 128 bits per line (4 words x 32 bits, BLOCK_WIDTH = 128)
//              - 6-bit index addressing (INDEX_WIDTH = 6)
//              - Synchronous write gated by write_enable on rising clock edge
//              - Combinational (asynchronous) read for single-cycle LOOKUP
//              - Parameterized dimensions for reconfigurability
//              - No reset on data array (RAM inference friendly, saves LUTs/FFs)
// =============================================================================

`timescale 1ns / 1ps

module cache_data_ram #(
    parameter NUM_LINES   = 64,
    parameter INDEX_WIDTH = 6,
    parameter BLOCK_WIDTH = 128
)(
    input  wire                   clk,
    input  wire [INDEX_WIDTH-1:0] index,
    input  wire                   write_enable,
    input  wire [BLOCK_WIDTH-1:0] write_data,
    output wire [BLOCK_WIDTH-1:0] read_data
);

    // =========================================================================
    // Storage Array Definition: 64 entries of 128-bit blocks
    // =========================================================================
    reg [BLOCK_WIDTH-1:0] ram [0:NUM_LINES-1];

    // =========================================================================
    // Combinational Read (Asynchronous Read Port)
    // =========================================================================
    // Enables immediate data availability during cache LOOKUP state.
    // In FPGA synthesis, this infers distributed RAM (LUTRAM) rather than Block RAM.
    // =========================================================================
    assign read_data = ram[index];

    // =========================================================================
    // Synchronous Write Process
    // =========================================================================
    // Data is committed on the rising edge of clk when write_enable is asserted.
    // Notice: Memory array is intentionally NOT reset to prevent the synthesis
    // tool from decomposing the array into 8,192 discrete flip-flops (64*128).
    // Lines are validated only via valid_bit_ram.
    // =========================================================================
    always @(posedge clk) begin
        if (write_enable) begin
            ram[index] <= write_data;
        end
    end

endmodule
