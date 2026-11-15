// =============================================================================
// Testbench:   tb_valid_bit_ram
// Designer:    Sankalp (Cache Storage & Address Decoding Specialist)
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Unit testbench for valid_bit_ram.v verifying:
//              - Active-high reset clears all 64 valid bits
//              - Independent write enable and write_valid operations
//              - Combinational validity inspection
//              - Selective line validation and invalidation
//              - Isolation between adjacent valid bits
//              - Runtime hardware reset invalidation
// =============================================================================

`timescale 1ns / 1ps

module tb_valid_bit_ram;

    localparam NUM_LINES   = 64;
    localparam INDEX_WIDTH = 6;

    reg                   clk;
    reg                   rst;
    reg [INDEX_WIDTH-1:0] index;
    reg                   write_enable;
    reg                   write_valid;
    wire                  read_valid;

    integer pass_count;
    integer fail_count;
    integer i;

    // 100MHz clock
    always #5 clk = ~clk;

    // Instantiate UUT
    valid_bit_ram #(
        .NUM_LINES   (NUM_LINES),
        .INDEX_WIDTH (INDEX_WIDTH)
    ) uut (
        .clk          (clk),
        .rst          (rst),
        .index        (index),
        .write_enable (write_enable),
        .write_valid  (write_valid),
        .read_valid   (read_valid)
    );

    initial begin
        clk          = 0;
        rst          = 1;
        index        = 0;
        write_enable = 0;
        write_valid  = 0;
        pass_count   = 0;
        fail_count   = 0;

        #20;
        rst = 0;
        #10;

        $display("===============================================================================");
        $display("STARTING VALID-BIT RAM UNIT VERIFICATION");
        $display("===============================================================================");

        // Test 1: Verify all 64 lines are 0 following reset
        $display("[STAGE 1] Verifying all 64 valid bits are 0 after reset...");
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            index = i[INDEX_WIDTH-1:0];
            #1;
            if (read_valid === 1'b0) begin
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Line %0d not 0 after reset! Got %b", i, read_valid);
                fail_count = fail_count + 1;
            end
        end

        // Test 2: Set valid bits to 1 for all 64 lines
        $display("[STAGE 2] Setting all 64 valid bits to 1...");
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            @(posedge clk);
            index        <= i[INDEX_WIDTH-1:0];
            write_enable <= 1'b1;
            write_valid  <= 1'b1;
        end

        @(posedge clk);
        write_enable <= 1'b0;
        #5;

        // Verify all 64 lines are now 1
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            index = i[INDEX_WIDTH-1:0];
            #1;
            if (read_valid === 1'b1) begin
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Line %0d not 1 after write! Got %b", i, read_valid);
                fail_count = fail_count + 1;
            end
        end

        // Test 3: Selectively invalidate line 15 (write_valid = 0)
        $display("[STAGE 3] Selectively invalidating line 15...");
        @(posedge clk);
        index        <= 6'd15;
        write_enable <= 1'b1;
        write_valid  <= 1'b0;

        @(posedge clk);
        write_enable <= 1'b0;
        #2;

        // Check line 15 is 0
        index = 6'd15;
        #1;
        if (read_valid === 1'b0) begin
            $display("[PASS] Line 15 invalidated to 0.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Line 15 invalidation failed!");
            fail_count = fail_count + 1;
        end

        // Check neighbor line 14 is still 1
        index = 6'd14;
        #1;
        if (read_valid === 1'b1) begin
            $display("[PASS] Line 14 remains valid (isolation intact).");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Line 14 corrupted!");
            fail_count = fail_count + 1;
        end

        // Check neighbor line 16 is still 1
        index = 6'd16;
        #1;
        if (read_valid === 1'b1) begin
            $display("[PASS] Line 16 remains valid (isolation intact).");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Line 16 corrupted!");
            fail_count = fail_count + 1;
        end

        // Test 4: Runtime reset invalidation
        $display("[STAGE 4] Testing runtime reset pulse...");
        @(posedge clk);
        rst <= 1'b1;
        #15;
        rst <= 1'b0;
        #5;

        // Check line 14 and 16 are cleared back to 0
        index = 6'd14;
        #1;
        if (read_valid === 1'b0) begin
            $display("[PASS] Runtime reset cleared line 14 to 0.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Runtime reset failed to clear line 14!");
            fail_count = fail_count + 1;
        end

        index = 6'd16;
        #1;
        if (read_valid === 1'b0) begin
            $display("[PASS] Runtime reset cleared line 16 to 0.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Runtime reset failed to clear line 16!");
            fail_count = fail_count + 1;
        end

        $display("===============================================================================");
        $display("VALID-BIT RAM VERIFICATION SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("===============================================================================");
        if (fail_count == 0)
            $display(">>> ALL VALID-BIT RAM TESTS PASSED <<<");
        else
            $display(">>> VALID-BIT RAM VERIFICATION FAILED <<<");

        $finish;
    end

endmodule

