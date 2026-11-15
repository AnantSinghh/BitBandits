// =============================================================================
// Testbench:   tb_cache_data_ram
// Designer:    Sankalp (Cache Storage & Address Decoding Specialist)
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Unit testbench for cache_data_ram.v verifying:
//              - Synchronous write on posedge clk
//              - Immediate combinational read
//              - Writing across all 64 lines
//              - Isolation (updating one line does not corrupt others)
//              - Write enable masking (no write when write_enable = 0)
// =============================================================================

`timescale 1ns / 1ps

module tb_cache_data_ram;

    localparam NUM_LINES   = 64;
    localparam INDEX_WIDTH = 6;
    localparam BLOCK_WIDTH = 128;

    reg                   clk;
    reg [INDEX_WIDTH-1:0] index;
    reg                   write_enable;
    reg [BLOCK_WIDTH-1:0] write_data;
    wire [BLOCK_WIDTH-1:0] read_data;

    integer pass_count;
    integer fail_count;
    integer i;

    // Clock generator (100MHz -> 10ns period)
    always #5 clk = ~clk;

    // Instantiate UUT
    cache_data_ram #(
        .NUM_LINES   (NUM_LINES),
        .INDEX_WIDTH (INDEX_WIDTH),
        .BLOCK_WIDTH (BLOCK_WIDTH)
    ) uut (
        .clk          (clk),
        .index        (index),
        .write_enable (write_enable),
        .write_data   (write_data),
        .read_data    (read_data)
    );

    reg [31:0] i_32;

    initial begin
        clk          = 0;
        index        = 0;
        write_enable = 0;
        write_data   = 0;
        pass_count   = 0;
        fail_count   = 0;

        #15;
        $display("===============================================================================");
        $display("STARTING CACHE DATA RAM UNIT VERIFICATION");
        $display("===============================================================================");

        // Test 1: Write all 64 lines with unique test patterns
        $display("[STAGE 1] Writing unique patterns to all 64 lines...");
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            i_32 = i;
            @(posedge clk);
            index        <= i[INDEX_WIDTH-1:0];
            write_enable <= 1'b1;
            write_data   <= {32'hDEADBEEF + i_32, 32'hCAFEBABE + i_32, 32'h12345678 + i_32, 32'h87654321 + i_32};
        end

        @(posedge clk);
        write_enable <= 1'b0;
        #5;

        // Test 2: Read back all 64 lines and verify data integrity
        $display("[STAGE 2] Verifying combinational read across all 64 lines...");
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            i_32 = i;
            index = i[INDEX_WIDTH-1:0];
            #2; // Combinational propagation
            if (read_data === {32'hDEADBEEF + i_32, 32'hCAFEBABE + i_32, 32'h12345678 + i_32, 32'h87654321 + i_32}) begin
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Line %0d: Expected 0x%032h, Got 0x%032h",
                         i, {32'hDEADBEEF + i, 32'hCAFEBABE + i, 32'h12345678 + i, 32'h87654321 + i}, read_data);
                fail_count = fail_count + 1;
            end
        end

        // Test 3: Verify single line update does not corrupt adjacent lines
        $display("[STAGE 3] Verifying line isolation (overwriting line 32)...");
        @(posedge clk);
        index        <= 6'd32;
        write_enable <= 1'b1;
        write_data   <= 128'hFFFF_FFFF_0000_0000_AAAA_AAAA_5555_5555;

        @(posedge clk);
        write_enable <= 1'b0;
        #2;

        // Check line 32 updated
        index = 6'd32;
        #2;
        if (read_data === 128'hFFFF_FFFF_0000_0000_AAAA_AAAA_5555_5555) begin
            $display("[PASS] Line 32 updated successfully.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Line 32 update failed!");
            fail_count = fail_count + 1;
        end

        // Check line 31 not corrupted
        index = 6'd31;
        #2;
        if (read_data === {32'hDEADBEEF + 32'd31, 32'hCAFEBABE + 32'd31, 32'h12345678 + 32'd31, 32'h87654321 + 32'd31}) begin
            $display("[PASS] Line 31 intact (not corrupted).");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Line 31 corrupted!");
            fail_count = fail_count + 1;
        end

        // Check line 33 not corrupted
        index = 6'd33;
        #2;
        if (read_data === {32'hDEADBEEF + 32'd33, 32'hCAFEBABE + 32'd33, 32'h12345678 + 32'd33, 32'h87654321 + 32'd33}) begin
            $display("[PASS] Line 33 intact (not corrupted).");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Line 33 corrupted!");
            fail_count = fail_count + 1;
        end

        // Test 4: Verify write_enable = 0 masks writes
        $display("[STAGE 4] Verifying write enable masking...");
        @(posedge clk);
        index        <= 6'd32;
        write_enable <= 1'b0;
        write_data   <= 128'h0;

        @(posedge clk);
        #2;
        index = 6'd32;
        #2;
        if (read_data === 128'hFFFF_FFFF_0000_0000_AAAA_AAAA_5555_5555) begin
            $display("[PASS] Write enable = 0 successfully protected data from being overwritten.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Write enable = 0 failed to protect data!");
            fail_count = fail_count + 1;
        end

        $display("===============================================================================");
        $display("CACHE DATA RAM VERIFICATION SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("===============================================================================");
        if (fail_count == 0)
            $display(">>> ALL CACHE DATA RAM TESTS PASSED <<<");
        else
            $display(">>> CACHE DATA RAM VERIFICATION FAILED <<<");

        $finish;
    end

endmodule
