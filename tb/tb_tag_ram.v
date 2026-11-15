// =============================================================================
// Testbench:   tb_tag_ram
// Designer:    Sankalp (Cache Storage & Address Decoding Specialist)
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Unit testbench for tag_ram.v verifying:
//              - Synchronous tag write on posedge clk
//              - Immediate combinational tag read
//              - Tag updates across all 64 lines
//              - Tag replacement / conflict simulation on same line
//              - Isolation of neighboring lines
//              - Write enable masking
// =============================================================================

`timescale 1ns / 1ps

module tb_tag_ram;

    localparam NUM_LINES   = 64;
    localparam INDEX_WIDTH = 6;
    localparam TAG_WIDTH   = 22;

    reg                   clk;
    reg [INDEX_WIDTH-1:0] index;
    reg                   write_enable;
    reg [TAG_WIDTH-1:0]   write_tag;
    wire [TAG_WIDTH-1:0]  read_tag;

    integer pass_count;
    integer fail_count;
    integer i;
    reg [TAG_WIDTH-1:0] expected_tag;

    // 100 MHz clock
    always #5 clk = ~clk;

    // Instantiate UUT
    tag_ram #(
        .NUM_LINES   (NUM_LINES),
        .INDEX_WIDTH (INDEX_WIDTH),
        .TAG_WIDTH   (TAG_WIDTH)
    ) uut (
        .clk          (clk),
        .index        (index),
        .write_enable (write_enable),
        .write_tag    (write_tag),
        .read_tag     (read_tag)
    );

    initial begin
        clk          = 0;
        index        = 0;
        write_enable = 0;
        write_tag    = 0;
        pass_count   = 0;
        fail_count   = 0;

        #15;
        $display("===============================================================================");
        $display("STARTING TAG RAM UNIT VERIFICATION");
        $display("===============================================================================");

        // Test 1: Write all 64 lines with unique 22-bit tags
        $display("[STAGE 1] Writing unique 22-bit tags to all 64 lines...");
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            @(posedge clk);
            index        <= i[INDEX_WIDTH-1:0];
            write_enable <= 1'b1;
            write_tag    <= (22'h1A5000 + (i * 22'h40));
        end

        @(posedge clk);
        write_enable <= 1'b0;
        #5;

        // Test 2: Read back all 64 lines and verify tags
        $display("[STAGE 2] Verifying combinational tag read across all 64 lines...");
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            index = i[INDEX_WIDTH-1:0];
            expected_tag = (22'h1A5000 + (i * 22'h40));
            #2;
            if (read_tag === expected_tag) begin
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Line %0d: Expected Tag 0x%06h, Got 0x%06h", i, expected_tag, read_tag);
                fail_count = fail_count + 1;
            end
        end

        // Test 3: Conflict scenario - overwrite line 20 with new tag (e.g., 0x000404 -> 0x000804)
        $display("[STAGE 3] Simulating conflict miss tag replacement on line 20...");
        @(posedge clk);
        index        <= 6'd20;
        write_enable <= 1'b1;
        write_tag    <= 22'h3FFFFF; // All ones tag

        @(posedge clk);
        write_enable <= 1'b0;
        #2;

        index = 6'd20;
        #2;
        if (read_tag === 22'h3FFFFF) begin
            $display("[PASS] Line 20 tag replaced with 0x3FFFFF.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Line 20 tag replacement failed! Got 0x%06h", read_tag);
            fail_count = fail_count + 1;
        end

        // Verify line 19 not corrupted
        index = 6'd19;
        expected_tag = (22'h1A5000 + (19 * 22'h40));
        #2;
        if (read_tag === expected_tag) begin
            $display("[PASS] Line 19 tag intact.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Line 19 tag corrupted!");
            fail_count = fail_count + 1;
        end

        // Verify line 21 not corrupted
        index = 6'd21;
        expected_tag = (22'h1A5000 + (21 * 22'h40));
        #2;
        if (read_tag === expected_tag) begin
            $display("[PASS] Line 21 tag intact.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Line 21 tag corrupted!");
            fail_count = fail_count + 1;
        end

        // Test 4: Write enable = 0 protection
        $display("[STAGE 4] Verifying write enable protection on line 20...");
        @(posedge clk);
        index        <= 6'd20;
        write_enable <= 1'b0;
        write_tag    <= 22'h000000;

        @(posedge clk);
        #2;
        index = 6'd20;
        #2;
        if (read_tag === 22'h3FFFFF) begin
            $display("[PASS] Line 20 protected from un-enabled write.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Line 20 overwritten despite write_enable = 0!");
            fail_count = fail_count + 1;
        end

        $display("===============================================================================");
        $display("TAG RAM VERIFICATION SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("===============================================================================");
        if (fail_count == 0)
            $display(">>> ALL TAG RAM TESTS PASSED <<<");
        else
            $display(">>> TAG RAM VERIFICATION FAILED <<<");

        $finish;
    end

endmodule

