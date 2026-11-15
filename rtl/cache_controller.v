// =============================================================================
// Module Name: cache_controller
// Designer:    Manas
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Direct-mapped cache controller FSM orchestrating CPU requests,
//              tag lookup, cache hit/miss evaluation, memory refill sequencing,
//              and CPU response generation.
//
// States:
//   - S_IDLE:        Wait for CPU request, assert cpu_ready
//   - S_LOOKUP:      Evaluate tag match and valid bit for requested line
//   - S_MEM_REQUEST: Initiate 16-byte block fetch from main memory
//   - S_MEM_WAIT:    Wait for memory interface ready signal (mem_req_ready)
//   - S_REFILL:      Write received 128-bit block into cache line and set valid
//   - S_RESPOND:     Extract 32-bit word, assert cpu_resp_valid, return to IDLE
// =============================================================================

`timescale 1ns / 1ps

module cache_controller #(
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 32,
    parameter BLOCK_WIDTH  = 128,
    parameter TAG_WIDTH    = 22,
    parameter INDEX_WIDTH  = 6,
    parameter OFFSET_WIDTH = 4
)(
    input  wire                    clk,
    input  wire                    rst,

    // CPU Interface
    input  wire                    cpu_req_valid,
    input  wire [ADDR_WIDTH-1:0]   cpu_req_addr,
    output reg                     cpu_ready,
    output reg                     cpu_resp_valid,
    output reg  [DATA_WIDTH-1:0]   cpu_resp_data,

    // Cache Storage Interface
    output wire [INDEX_WIDTH-1:0]  storage_read_index,
    input  wire                    storage_read_valid,
    input  wire [TAG_WIDTH-1:0]    storage_read_tag,
    input  wire [BLOCK_WIDTH-1:0]  storage_read_data,

    output reg                     storage_write_en,
    output reg  [INDEX_WIDTH-1:0]  storage_write_index,
    output reg  [TAG_WIDTH-1:0]    storage_write_tag,
    output reg  [BLOCK_WIDTH-1:0]  storage_write_data,
    output reg                     storage_write_valid,

    // Tag Comparator Interface
    output wire [TAG_WIDTH-1:0]    comp_stored_tag,
    output wire [TAG_WIDTH-1:0]    comp_req_tag,
    output wire                    comp_stored_valid,
    input  wire                    comp_hit,
    input  wire                    comp_miss,

    // Memory Interface
    output reg                     mem_req,
    output reg  [ADDR_WIDTH-1:0]   mem_addr,
    input  wire                    mem_req_ready,
    input  wire [BLOCK_WIDTH-1:0]  mem_data,

    // Status / Diagnostic outputs
    output wire [2:0]              fsm_state,
    output reg                     cache_hit_flag,
    output reg                     cache_miss_flag
);

    // =========================================================================
    // FSM State Encoding
    // =========================================================================
    localparam [2:0] S_IDLE        = 3'b000;
    localparam [2:0] S_LOOKUP      = 3'b001;
    localparam [2:0] S_MEM_REQUEST = 3'b010;
    localparam [2:0] S_MEM_WAIT    = 3'b011;
    localparam [2:0] S_REFILL      = 3'b100;
    localparam [2:0] S_RESPOND     = 3'b101;

    reg [2:0] current_state, next_state;

    // Export current state for verification and top-level monitoring
    assign fsm_state = current_state;

    // =========================================================================
    // State Register (Sequential Process)
    // =========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= S_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // =========================================================================
    // Next-State Logic (Combinational Process - Initial Skeleton)
    // =========================================================================
    always @(*) begin
        next_state = current_state;
        case (current_state)
            S_IDLE: begin
                if (cpu_req_valid)
                    next_state = S_LOOKUP;
                else
                    next_state = S_IDLE;
            end

            S_LOOKUP: begin
                if (comp_hit)
                    next_state = S_RESPOND;
                else
                    next_state = S_MEM_REQUEST;
            end

            S_MEM_REQUEST: begin
                next_state = S_MEM_WAIT;
            end

            S_MEM_WAIT: begin
                if (mem_req_ready)
                    next_state = S_REFILL;
                else
                    next_state = S_MEM_WAIT;
            end

            S_REFILL: begin
                next_state = S_RESPOND;
            end

            S_RESPOND: begin
                next_state = S_IDLE;
            end

            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // Default driver assignments for initial compilation check
    assign storage_read_index = {INDEX_WIDTH{1'b0}};
    assign comp_stored_tag    = storage_read_tag;
    assign comp_req_tag       = {TAG_WIDTH{1'b0}};
    assign comp_stored_valid  = storage_read_valid;

    always @(*) begin
        cpu_ready           = (current_state == S_IDLE);
        cpu_resp_valid      = 1'b0;
        cpu_resp_data       = {DATA_WIDTH{1'b0}};
        storage_write_en    = 1'b0;
        storage_write_index = {INDEX_WIDTH{1'b0}};
        storage_write_tag   = {TAG_WIDTH{1'b0}};
        storage_write_data  = {BLOCK_WIDTH{1'b0}};
        storage_write_valid = 1'b0;
        mem_req             = 1'b0;
        mem_addr            = {ADDR_WIDTH{1'b0}};
        cache_hit_flag      = 1'b0;
        cache_miss_flag     = 1'b0;
    end

endmodule
