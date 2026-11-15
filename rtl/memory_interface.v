// =============================================================================
// Module Name : memory_interface
// Designer    : Tejas
// Project     : Design and Analysis of a Direct-Mapped Cache Controller
// Branch      : feature/main-memory-interface
// Date        : 2026-11-15
//
// Description :
//   Protocol bridge between the cache_controller FSM (Manas) and the
//   main_memory model (Tejas).  Implements the agreed request/response
//   handshake using a three-state interface FSM:
//
//     MEM_IDLE     – waiting for cache_controller to assert mem_req.
//     MEM_ACCESS   – mem_req latched; single-cycle enable pulse fired to
//                    main_memory; waiting for phy_mem_ready.
//     MEM_RESPONSE – phy_mem_rdata captured; mem_req_ready asserted to
//                    cache_controller for one cycle; return to IDLE.
//
//   Handshake contract (agreed with Manas / cache_controller):
//     Controller side  : mem_req        – single-cycle pulse in S_MEM_REQUEST
//                        mem_req_ready  – deasserted until block is available
//                        mem_data       – stable 128-bit block when ready
//     Memory side      : phy_mem_en     – single-cycle enable (never held)
//                        phy_mem_ready  – single-cycle from main_memory
//                        phy_mem_rdata  – captured into internal buffer
//
//   Signals exported to cache_controller (Manas interface):
//     mem_req_valid  – driven by controller; captured here on assertion
//     mem_req_addr   – block-aligned address from controller
//     mem_req_ready  – ready flag back to controller (one-cycle pulse)
//     mem_req_data   – 128-bit block data back to controller
//
//   The in_flight guard prevents the same memory request from being accepted
//   twice if mem_req remains high for more than one clock.
//
//   Synthesisability note:
//     All logic is synchronous sequential or simple combinational.
//     No `#delay` or $display outside `ifdef SIMULATION guards.
// =============================================================================

`timescale 1ns / 1ps

module memory_interface #(
    parameter ADDR_WIDTH  = 32,
    parameter BLOCK_WIDTH = 128
)(
    input  wire                    clk,
    input  wire                    rst,

    // -------------------------------------------------------------------------
    // Controller Interface  (connects to cache_controller.v – Manas)
    // -------------------------------------------------------------------------
    input  wire                    mem_req,          // Single-cycle pulse from controller
    input  wire [ADDR_WIDTH-1:0]   mem_addr,         // Block-aligned address (bits[3:0]=0)
    output reg                     mem_req_ready,    // One-cycle completion flag to controller
    output reg  [BLOCK_WIDTH-1:0]  mem_data,         // 128-bit block data to controller

    // -------------------------------------------------------------------------
    // Physical Memory Interface  (connects to main_memory.v)
    // -------------------------------------------------------------------------
    output reg                     phy_mem_en,       // Single-cycle enable to main_memory
    output reg  [ADDR_WIDTH-1:0]   phy_mem_addr,     // Address forwarded to main_memory
    input  wire                    phy_mem_ready,    // Ready strobe from main_memory
    input  wire [BLOCK_WIDTH-1:0]  phy_mem_rdata     // 128-bit data from main_memory
);

    // =========================================================================
    // FSM State Encoding
    // =========================================================================
    localparam [1:0] MI_IDLE     = 2'b00;
    localparam [1:0] MI_ACCESS   = 2'b01;
    localparam [1:0] MI_RESPONSE = 2'b10;

    reg [1:0]            mi_state;
    reg [ADDR_WIDTH-1:0] latched_addr;   // Holds address stable during wait
    reg                  en_pulse_sent;  // Ensures phy_mem_en fires only once

    // =========================================================================
    // Sequential FSM
    // =========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mi_state       <= MI_IDLE;
            mem_req_ready  <= 1'b0;
            mem_data       <= {BLOCK_WIDTH{1'b0}};
            phy_mem_en     <= 1'b0;
            phy_mem_addr   <= {ADDR_WIDTH{1'b0}};
            latched_addr   <= {ADDR_WIDTH{1'b0}};
            en_pulse_sent  <= 1'b0;
        end else begin
            case (mi_state)

                // -------------------------------------------------------------
                // MI_IDLE : Wait for cache_controller to issue mem_req.
                //   Latch address and transition to MI_ACCESS.
                //   in_flight protection: only transitions when in MI_IDLE,
                //   so a sustained mem_req cannot re-trigger the transaction.
                // -------------------------------------------------------------
                MI_IDLE: begin
                    mem_req_ready <= 1'b0;
                    phy_mem_en    <= 1'b0;
                    en_pulse_sent <= 1'b0;
                    if (mem_req) begin
                        latched_addr  <= mem_addr;
                        mi_state      <= MI_ACCESS;
                        `ifdef SIMULATION
                        $display("[MEM_INTF @%0t] Request captured: addr=0x%08h", $time, mem_addr);
                        `endif
                    end
                end

                // -------------------------------------------------------------
                // MI_ACCESS : Issue a single-cycle enable pulse to main_memory,
                //   then wait for phy_mem_ready.
                //   en_pulse_sent ensures phy_mem_en is high for exactly one
                //   clock cycle, preventing main_memory from re-starting.
                // -------------------------------------------------------------
                MI_ACCESS: begin
                    mem_req_ready <= 1'b0;

                    if (!en_pulse_sent) begin
                        // Fire the single-cycle enable to main_memory
                        phy_mem_en    <= 1'b1;
                        phy_mem_addr  <= latched_addr;
                        en_pulse_sent <= 1'b1;
                    end else begin
                        // Deassert after the first cycle
                        phy_mem_en <= 1'b0;
                    end

                    if (phy_mem_ready) begin
                        // Capture returned block into buffer
                        mem_data  <= phy_mem_rdata;
                        mi_state  <= MI_RESPONSE;
                        `ifdef SIMULATION
                        $display("[MEM_INTF @%0t] Data received:    addr=0x%08h, data=0x%032h",
                                 $time, latched_addr, phy_mem_rdata);
                        `endif
                    end
                end

                // -------------------------------------------------------------
                // MI_RESPONSE : Assert mem_req_ready for exactly one cycle so
                //   cache_controller's S_MEM_WAIT → S_REFILL transition fires.
                //   Return to MI_IDLE immediately.
                // -------------------------------------------------------------
                MI_RESPONSE: begin
                    mem_req_ready <= 1'b1;
                    phy_mem_en    <= 1'b0;
                    mi_state      <= MI_IDLE;
                    `ifdef SIMULATION
                    $display("[MEM_INTF @%0t] Ready asserted:   addr=0x%08h", $time, latched_addr);
                    `endif
                end

                default: begin
                    mi_state      <= MI_IDLE;
                    mem_req_ready <= 1'b0;
                    phy_mem_en    <= 1'b0;
                end

            endcase
        end
    end

endmodule
