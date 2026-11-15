// =============================================================================
// Module Name: cache_controller
// Designer:    Manas
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Direct-mapped cache controller FSM orchestrating CPU requests,
//              tag lookup, cache hit/miss evaluation, memory refill sequencing,
//              and CPU response generation.
//
// Technical Ownership:
//   - Controller FSM implementation (IDLE, LOOKUP, MEM_REQUEST, MEM_WAIT, REFILL, RESPOND)
//   - Request latching and one-request-at-a-time protocol
//   - Cache hit/miss control logic
//   - Refill sequencing and block alignment
//   - CPU response generation and word selection
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

    // Export current state
    assign fsm_state = current_state;

    // =========================================================================
    // Internal Registers for Request Latching
    // =========================================================================
    reg [ADDR_WIDTH-1:0] latched_addr;

    // Address field decoding from latched address:
    // Tag:          latched_addr[31:10] (22 bits)
    // Index:        latched_addr[9:4]   (6 bits)
    // Block offset: latched_addr[3:0]   (4 bits)
    // Word select:  latched_addr[3:2]   (2 bits)
    wire [TAG_WIDTH-1:0]   req_tag      = latched_addr[31:10];
    wire [INDEX_WIDTH-1:0] req_index    = latched_addr[9:4];
    wire [1:0]             req_word_sel = latched_addr[3:2];

    // Read index to cache storage during lookup
    assign storage_read_index = (current_state == S_IDLE && cpu_req_valid) ?
                                cpu_req_addr[9:4] : req_index;

    // Route tags and valid flag to comparator
    assign comp_stored_tag   = storage_read_tag;
    assign comp_req_tag      = req_tag;
    assign comp_stored_valid = storage_read_valid;

    // =========================================================================
    // Sequential Process: State Transition and Address Latching
    // =========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= S_IDLE;
            latched_addr  <= {ADDR_WIDTH{1'b0}};
        end else begin
            current_state <= next_state;

            // Latch CPU address upon transitioning from IDLE on a valid request
            if (current_state == S_IDLE && cpu_req_valid) begin
                latched_addr <= cpu_req_addr;
            end
        end
    end

    // =========================================================================
    // Next-State Logic (Combinational Process)
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

    // =========================================================================
    // Output Generation (Combinational Default & State-Specific Logic)
    // =========================================================================
    always @(*) begin
        // Ready only in IDLE state; controller is busy during all other states
        cpu_ready           = (current_state == S_IDLE);
        cpu_resp_valid      = 1'b0;
        cpu_resp_data       = {DATA_WIDTH{1'b0}};

        storage_write_en    = 1'b0;
        storage_write_index = req_index;
        storage_write_tag   = req_tag;
        storage_write_data  = {BLOCK_WIDTH{1'b0}};
        storage_write_valid = 1'b0;

        mem_req             = 1'b0;
        mem_addr            = {latched_addr[31:4], 4'b0000}; // Block aligned
        cache_hit_flag      = 1'b0;
        cache_miss_flag     = 1'b0;
    end

endmodule
