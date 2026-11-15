// =============================================================================
// Module Name: valid_bit_ram
// Designer:    Sankalp (Cache Storage & Address Decoding Specialist)
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Synchronous-write, combinational-read cache valid-bit array:
//              - 64 Cache lines (NUM_LINES = 64, INDEX_WIDTH = 6)
//              - 1-bit valid flag per line (total 64 bits)
//              - Active-high reset clears all 64 valid bits to 1'b0 (prevents false hits)
//              - Independent write enable and write_valid data input
//              - Combinational read port to provide instant validity status for LOOKUP
//              - Clean synthesizable RTL with parameterized line count
// =============================================================================

`timescale 1ns / 1ps

module valid_bit_ram #(
    parameter NUM_LINES   = 64,
    parameter INDEX_WIDTH = 6
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire [INDEX_WIDTH-1:0] index,
    input  wire                   write_enable,
    input  wire                   write_valid,
    output wire                   read_valid
);

    // =========================================================================
    // Storage Array: 64 discrete valid flip-flops
    // =========================================================================
    reg valid_mem [0:NUM_LINES-1];

    integer i;

    // =========================================================================
    // Combinational Read (Asynchronous Read Port)
    // =========================================================================
    // Provides immediate validity status corresponding to the selected index.
    // Tag comparator gates the tag comparison result with this valid bit.
    // =========================================================================
    assign read_valid = valid_mem[index];

    // =========================================================================
    // Synchronous Write & Asynchronous Active-High Reset Process
    // =========================================================================
    // - On reset (rst = 1): All 64 valid bits are cleared to 0 simultaneously.
    //   This ensures zero false hits on cold boot without wasting resources
    //   resetting data RAM (8192 bits) or tag RAM (1408 bits).
    // - On clock edge with write_enable: The selected valid bit is updated.
    // =========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid_mem[i] <= 1'b0;
            end
        end else if (write_enable) begin
            valid_mem[index] <= write_valid;
        end
    end

endmodule

