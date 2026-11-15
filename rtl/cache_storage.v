// =============================================================================
// Module Name: cache_storage
// Designer:    Tejas
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Direct-mapped cache storage array:
//              - 64 Cache Lines
//              - 128-bit Data Block per line (4 words x 32 bits)
//              - 22-bit Tag per line
//              - 1-bit Valid flag per line
//              Supports combinational read for LOOKUP evaluation and
//              synchronous write on REFILL. Active-high reset invalidates all lines.
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
    
    // Read port (combinational for LOOKUP stage)
    input  wire [INDEX_WIDTH-1:0] read_index,
    output wire                   read_valid,
    output wire [TAG_WIDTH-1:0]   read_tag,
    output wire [BLOCK_WIDTH-1:0] read_data,

    // Write / Refill port (synchronous)
    input  wire                   write_en,
    input  wire [INDEX_WIDTH-1:0] write_index,
    input  wire [TAG_WIDTH-1:0]   write_tag,
    input  wire [BLOCK_WIDTH-1:0] write_data,
    input  wire                   write_valid
);

    // Storage arrays
    reg [BLOCK_WIDTH-1:0] data_mem [0:NUM_LINES-1];
    reg [TAG_WIDTH-1:0]   tag_mem  [0:NUM_LINES-1];
    reg                   valid_mem[0:NUM_LINES-1];

    integer i;

    // Asynchronous / combinational read
    assign read_valid = valid_mem[read_index];
    assign read_tag   = tag_mem[read_index];
    assign read_data  = data_mem[read_index];

    // Synchronous write / reset logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid_mem[i] <= 1'b0;
                tag_mem[i]   <= {TAG_WIDTH{1'b0}};
                data_mem[i]  <= {BLOCK_WIDTH{1'b0}};
            end
        end else if (write_en) begin
            valid_mem[write_index] <= write_valid;
            tag_mem[write_index]   <= write_tag;
            data_mem[write_index]  <= write_data;
        end
    end

endmodule
