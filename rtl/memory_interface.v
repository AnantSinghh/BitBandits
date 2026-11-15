// =============================================================================
// Module Name: memory_interface
// Designer:    Anant
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Manages the request/response handshake protocol between the
//              Cache Controller and the Main Memory system. Ensures single-request
//              issuance, holds address stable during memory wait cycles, and
//              delivers received 128-bit block data back to controller.
// =============================================================================

`timescale 1ns / 1ps

module memory_interface #(
    parameter ADDR_WIDTH  = 32,
    parameter BLOCK_WIDTH = 128
)(
    input  wire                   clk,
    input  wire                   rst,

    // Controller Interface
    input  wire                   mem_req,       // Request trigger from controller
    input  wire [ADDR_WIDTH-1:0]  mem_addr,      // Block-aligned address
    output reg                    mem_req_ready, // Handshake completion signal
    output reg  [BLOCK_WIDTH-1:0] mem_data,      // 128-bit block data to controller

    // Memory Physical Interface
    output reg                    phy_mem_en,
    output reg  [ADDR_WIDTH-1:0]  phy_mem_addr,
    input  wire                   phy_mem_ready,
    input  wire [BLOCK_WIDTH-1:0] phy_mem_rdata
);

    reg in_flight;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_req_ready <= 1'b0;
            mem_data      <= {BLOCK_WIDTH{1'b0}};
            phy_mem_en    <= 1'b0;
            phy_mem_addr  <= {ADDR_WIDTH{1'b0}};
            in_flight     <= 1'b0;
        end else begin
            if (mem_req && !in_flight) begin
                // Initiate single request pulse to main memory
                phy_mem_en   <= 1'b1;
                phy_mem_addr <= mem_addr;
                in_flight    <= 1'b1;
                mem_req_ready <= 1'b0;
            end else if (in_flight) begin
                phy_mem_en <= 1'b0; // Deassert enable after 1 cycle to prevent re-triggering
                if (phy_mem_ready) begin
                    mem_data      <= phy_mem_rdata;
                    mem_req_ready <= 1'b1;
                    in_flight     <= 1'b0;
                end else begin
                    mem_req_ready <= 1'b0;
                end
            end else begin
                mem_req_ready <= 1'b0;
                phy_mem_en    <= 1'b0;
            end
        end
    end

endmodule
