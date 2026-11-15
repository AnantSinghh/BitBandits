// =============================================================================
// Module Name : main_memory
// Designer    : Tejas
// Project     : Design and Analysis of a Direct-Mapped Cache Controller
// Branch      : feature/main-memory-interface
// Date        : 2026-11-15
//
// Description :
//   Behavioral / synthesizable main memory model supplying 128-bit (16-byte)
//   cache-line blocks to the memory_interface module.
//
//   Key design decisions:
//     - Single-port read-only memory (cache is read-only per spec).
//     - Configurable latency LATENCY parameter (default 10 cycles).
//     - Deterministic address-based data pattern for independent verification.
//     - Internal FSM (IDLE → ACCESS → RESPONSE) prevents re-triggering.
//     - Latency counter width auto-sized to hold LATENCY value.
//     - No `#delay` constructs — fully synthesizable RTL.
//
//   Data pattern (each 32-bit word within a block):
//     word[0] = { block_addr[31:4], 4'h0, 12'hA01 }   (bytes  0-3  of block)
//     word[1] = { block_addr[31:4], 4'h4, 12'hB02 }   (bytes  4-7  of block)
//     word[2] = { block_addr[31:4], 4'h8, 12'hC03 }   (bytes  8-11 of block)
//     word[3] = { block_addr[31:4], 4'hC, 12'hD04 }   (bytes 12-15 of block)
//
//   Address space modelled:
//     Full 32-bit address range (4 GB) using combinational generation.
//     No physical storage array; block data is computed from the address.
//     This eliminates the need for $readmemh / $readmemb and allows any
//     32-bit block-aligned address to be served without depth constraints.
//
//   Synthesisability note:
//     The generate_block_data function uses only bit-select and concatenation,
//     which are synthesisable constructs. LATENCY and counter logic are also
//     synthesisable. Only $display statements are simulation-only and must be
//     guarded by `ifdef SIMULATION or removed for synthesis.
// =============================================================================

`timescale 1ns / 1ps

module main_memory #(
    parameter ADDR_WIDTH  = 32,         // CPU address bus width
    parameter BLOCK_WIDTH = 128,        // Cache-line / block width in bits
    parameter LATENCY     = 10          // Memory access latency in clock cycles
                                        //   (minimum 1; set ≥ 1 for real simulation)
)(
    input  wire                    clk,
    input  wire                    rst,

    // Physical memory interface (driven by memory_interface.v)
    input  wire                    mem_en,          // Request strobe (single-cycle pulse)
    input  wire [ADDR_WIDTH-1:0]   mem_addr,        // Block-aligned address

    output reg                     mem_ready,       // High for one cycle when data valid
    output reg  [BLOCK_WIDTH-1:0]  mem_rdata        // 128-bit block data
);

    // =========================================================================
    // Local parameter: counter width to hold LATENCY value
    // =========================================================================
    localparam CNT_WIDTH = 4;   // Supports LATENCY up to 15 cycles.
                                // Increase to 5+ for LATENCY > 15.

    // =========================================================================
    // FSM state encoding  (MEM_IDLE → MEM_ACCESS → MEM_RESPONSE)
    // =========================================================================
    localparam [1:0] MEM_IDLE     = 2'b00;
    localparam [1:0] MEM_ACCESS   = 2'b01;
    localparam [1:0] MEM_RESPONSE = 2'b10;

    reg [1:0]            state;
    reg [CNT_WIDTH-1:0]  counter;
    reg [ADDR_WIDTH-1:0] latched_addr;

    // =========================================================================
    // Deterministic block-data generation (purely combinational function)
    //   Input : block-aligned 32-bit address (bits [3:0] must be 0)
    //   Output: 128-bit data block packed as { word3, word2, word1, word0 }
    //           where word0 occupies the LSBs (little-endian word order)
    // =========================================================================
    function [127:0] generate_block_data;
        input [31:0] b_addr;
        reg [31:0] w0, w1, w2, w3;
        begin
            // Each word embeds the block address MSBs for unique identification.
            // The lower nibble of the byte-address selects the word within the block.
            // The 12-bit suffix provides an easily recognisable marker.
            w0 = {b_addr[31:4], 4'h0, 12'hA01};
            w1 = {b_addr[31:4], 4'h4, 12'hB02};
            w2 = {b_addr[31:4], 4'h8, 12'hC03};
            w3 = {b_addr[31:4], 4'hC, 12'hD04};
            // Packed as { word3[127:96], word2[95:64], word1[63:32], word0[31:0] }
            generate_block_data = {w3, w2, w1, w0};
        end
    endfunction

    // =========================================================================
    // Sequential FSM
    // =========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= MEM_IDLE;
            counter      <= {CNT_WIDTH{1'b0}};
            latched_addr <= {ADDR_WIDTH{1'b0}};
            mem_ready    <= 1'b0;
            mem_rdata    <= {BLOCK_WIDTH{1'b0}};
        end else begin
            case (state)

                // -----------------------------------------------------------------
                // MEM_IDLE : Wait for a valid request strobe.
                //   Latch the address and start the latency counter.
                //   mem_en is expected to be a single-cycle pulse from
                //   memory_interface; the in_flight guard there prevents re-entry.
                // -----------------------------------------------------------------
                MEM_IDLE: begin
                    mem_ready <= 1'b0;
                    if (mem_en) begin
                        latched_addr <= mem_addr;
                        // Load counter with (LATENCY - 1) so that after
                        // LATENCY - 1 decrement steps we reach zero in
                        // MEM_ACCESS and move to MEM_RESPONSE on the next edge.
                        counter <= LATENCY[CNT_WIDTH-1:0] - 1'b1;
                        state   <= MEM_ACCESS;
                        `ifdef SIMULATION
                        $display("[MAIN_MEM @%0t] Request accepted: addr=0x%08h, latency=%0d cycles",
                                 $time, mem_addr, LATENCY);
                        `endif
                    end
                end

                // -----------------------------------------------------------------
                // MEM_ACCESS : Count down the simulated access latency.
                //   Each posedge decrements the counter.
                //   When counter reaches 0 the access latency has been served.
                // -----------------------------------------------------------------
                MEM_ACCESS: begin
                    mem_ready <= 1'b0;
                    if (counter == {CNT_WIDTH{1'b0}}) begin
                        // Latency expired — drive data and ready next cycle
                        mem_rdata <= generate_block_data(latched_addr);
                        state     <= MEM_RESPONSE;
                    end else begin
                        counter <= counter - 1'b1;
                    end
                end

                // -----------------------------------------------------------------
                // MEM_RESPONSE : Assert mem_ready for exactly one cycle.
                //   Return to IDLE immediately after so the interface can
                //   service the next request.
                // -----------------------------------------------------------------
                MEM_RESPONSE: begin
                    mem_ready <= 1'b1;
                    state     <= MEM_IDLE;
                    `ifdef SIMULATION
                    $display("[MAIN_MEM @%0t] Response issued:  addr=0x%08h, data=0x%032h",
                             $time, latched_addr, mem_rdata);
                    `endif
                end

                default: begin
                    state     <= MEM_IDLE;
                    mem_ready <= 1'b0;
                end

            endcase
        end
    end

endmodule
