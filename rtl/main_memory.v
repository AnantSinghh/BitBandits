// =============================================================================
// Module Name: main_memory
// Designer:    Anant
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Behavioral / synthesizable memory model providing 128-bit blocks
//              (16 bytes) with configurable read latency (LATENCY cycles).
//              Initializes memory array with predictable patterns for verification:
//              Each 32-bit word = {addr[31:4], word_index[3:0], 12'hABC}.
// =============================================================================

`timescale 1ns / 1ps

module main_memory #(
    parameter ADDR_WIDTH  = 32,
    parameter BLOCK_WIDTH = 128,
    parameter LATENCY     = 2     // Clock cycles before data is ready
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   mem_en,
    input  wire [ADDR_WIDTH-1:0]  mem_addr,
    output reg                    mem_ready,
    output reg  [BLOCK_WIDTH-1:0] mem_rdata
);

    reg [2:0] latency_counter;
    reg       busy;

    // Word generation function for testability:
    // Produces unique identifiable 32-bit words for any block address.
    function [127:0] generate_block_data;
        input [31:0] b_addr;
        reg [31:0] w0, w1, w2, w3;
        begin
            // 4 words: w0 (bytes 0-3), w1 (bytes 4-7), w2 (bytes 8-11), w3 (bytes 12-15)
            w0 = {b_addr[31:4], 4'h0, 12'hA01};
            w1 = {b_addr[31:4], 4'h4, 12'hB02};
            w2 = {b_addr[31:4], 4'h8, 12'hC03};
            w3 = {b_addr[31:4], 4'hC, 12'hD04};
            generate_block_data = {w3, w2, w1, w0};
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            latency_counter <= 3'd0;
            busy            <= 1'b0;
            mem_ready       <= 1'b0;
            mem_rdata       <= {BLOCK_WIDTH{1'b0}};
        end else begin
            if (mem_en && !busy) begin
                busy            <= 1'b1;
                latency_counter <= LATENCY;
                mem_ready       <= 1'b0;
            end else if (busy) begin
                if (latency_counter > 3'd1) begin
                    latency_counter <= latency_counter - 1'b1;
                    mem_ready       <= 1'b0;
                end else if (latency_counter == 3'd1) begin
                    latency_counter <= 3'd0;
                    mem_ready       <= 1'b1;
                    mem_rdata       <= generate_block_data(mem_addr);
                    busy            <= 1'b0;
                end
            end else begin
                mem_ready <= 1'b0;
            end
        end
    end

endmodule
