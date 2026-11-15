// =============================================================================
// Testbench:   tb_address_decoder
// Designer:    Sankalp (Cache Storage & Address Decoding Specialist)
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Unit verification for address_decoder.v covering:
//              - Field boundary alignment (tag, index, block offset, word sel, byte offset)
//              - Block-aligned address generation for memory refill
//              - All 64 index values
//              - Extreme corner cases (0x00000000, 0xFFFFFFFF)
//              - Same index with distinct tags (conflict cases)
// =============================================================================

`timescale 1ns / 1ps

module tb_address_decoder;

    localparam ADDR_WIDTH        = 32;
    localparam TAG_WIDTH         = 22;
    localparam INDEX_WIDTH       = 6;
    localparam OFFSET_WIDTH      = 4;
    localparam WORD_SEL_WIDTH    = 2;
    localparam BYTE_OFFSET_WIDTH = 2;

    reg  [ADDR_WIDTH-1:0]        tb_addr;
    wire [TAG_WIDTH-1:0]         tb_tag;
    wire [INDEX_WIDTH-1:0]       tb_index;
    wire [OFFSET_WIDTH-1:0]      tb_block_offset;
    wire [WORD_SEL_WIDTH-1:0]    tb_word_sel;
    wire [BYTE_OFFSET_WIDTH-1:0] tb_byte_offset;
    wire [ADDR_WIDTH-1:0]        tb_block_addr;

    integer pass_count;
    integer fail_count;

    // Instantiate Unit Under Test (UUT)
    address_decoder #(
        .ADDR_WIDTH        (ADDR_WIDTH),
        .TAG_WIDTH         (TAG_WIDTH),
        .INDEX_WIDTH       (INDEX_WIDTH),
        .OFFSET_WIDTH      (OFFSET_WIDTH),
        .WORD_SEL_WIDTH    (WORD_SEL_WIDTH),
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH)
    ) uut (
        .addr         (tb_addr),
        .tag          (tb_tag),
        .index        (tb_index),
        .block_offset (tb_block_offset),
        .word_sel     (tb_word_sel),
        .byte_offset  (tb_byte_offset),
        .block_addr   (tb_block_addr)
    );

    task check_decode(
        input [ADDR_WIDTH-1:0]        in_addr,
        input [TAG_WIDTH-1:0]         exp_tag,
        input [INDEX_WIDTH-1:0]       exp_index,
        input [OFFSET_WIDTH-1:0]      exp_block_offset,
        input [WORD_SEL_WIDTH-1:0]    exp_word_sel,
        input [BYTE_OFFSET_WIDTH-1:0] exp_byte_offset,
        input [ADDR_WIDTH-1:0]        exp_block_addr,
        input [127:0]                 test_desc
    );
        begin
            tb_addr = in_addr;
            #1; // Wait for combinational propagation

            if (tb_tag          === exp_tag          &&
                tb_index        === exp_index        &&
                tb_block_offset === exp_block_offset &&
                tb_word_sel     === exp_word_sel     &&
                tb_byte_offset  === exp_byte_offset  &&
                tb_block_addr   === exp_block_addr) begin
                $display("[PASS] %s | Addr: 0x%08h -> Tag: 0x%06h, Index: 0x%02h (%0d), Offset: 0x%h, Word: %0d, Byte: %0d, BlkAddr: 0x%08h",
                         test_desc, in_addr, tb_tag, tb_index, tb_index, tb_block_offset, tb_word_sel, tb_byte_offset, tb_block_addr);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %s | Addr: 0x%08h", test_desc, in_addr);
                if (tb_tag !== exp_tag)
                    $display("       Tag mismatch! Expected: 0x%06h, Got: 0x%06h", exp_tag, tb_tag);
                if (tb_index !== exp_index)
                    $display("       Index mismatch! Expected: 0x%02h, Got: 0x%02h", exp_index, tb_index);
                if (tb_block_offset !== exp_block_offset)
                    $display("       Block offset mismatch! Expected: 0x%h, Got: 0x%h", exp_block_offset, tb_block_offset);
                if (tb_word_sel !== exp_word_sel)
                    $display("       Word sel mismatch! Expected: %0d, Got: %0d", exp_word_sel, tb_word_sel);
                if (tb_byte_offset !== exp_byte_offset)
                    $display("       Byte offset mismatch! Expected: %0d, Got: %0d", exp_byte_offset, tb_byte_offset);
                if (tb_block_addr !== exp_block_addr)
                    $display("       Block addr mismatch! Expected: 0x%08h, Got: 0x%08h", exp_block_addr, tb_block_addr);
                fail_count = fail_count + 1;
            end
        end
    endtask

    integer idx;
    reg [ADDR_WIDTH-1:0] sweep_addr;

    initial begin
        pass_count = 0;
        fail_count = 0;
        tb_addr    = 32'h0000_0000;
        #5;

        $display("===============================================================================");
        $display("STARTING ADDRESS DECODER VERIFICATION SUITE");
        $display("===============================================================================");

        // Test 1: Zero Address
        check_decode(32'h0000_0000, 22'h000000, 6'h00, 4'h0, 2'b00, 2'b00, 32'h0000_0000, "All Zeros Boundary");

        // Test 2: Full Ones Address
        check_decode(32'hFFFF_FFFF, 22'h3FFFFF, 6'h3F, 4'hF, 2'b11, 2'b11, 32'hFFFF_FFF0, "All Ones Boundary ");

        // Test 3: Standard Project Benchmark Address 0x00001204
        // Tag:   32'h00001204 >> 10 = 22'h000004
        // Index: (32'h00001204 >> 4) & 6'h3F = 6'h20 (decimal 32)
        // Block Offset: 4'h4, Word: 2'b01 (word 1), Byte: 2'b00
        // Block Addr:   32'h00001200
        check_decode(32'h0000_1204, 22'h000004, 6'h20, 4'h4, 2'b01, 2'b00, 32'h0000_1200, "Benchmark Addr A  ");

        // Test 4: Same Block, Different Word (0x0000120C -> Word 3)
        check_decode(32'h0000_120C, 22'h000004, 6'h20, 4'hC, 2'b11, 2'b00, 32'h0000_1200, "Spatial Word 3    ");

        // Test 5: Same Block, Byte Offset 3 (0x00001207 -> Word 1, Byte 3)
        check_decode(32'h0000_1207, 22'h000004, 6'h20, 4'h7, 2'b01, 2'b11, 32'h0000_1200, "Sub-word Byte 3   ");

        // Test 6: Conflict Address with same index (0x00101204 -> Tag 0x000404, Index 0x20)
        check_decode(32'h0010_1204, 22'h000404, 6'h20, 4'h4, 2'b01, 2'b00, 32'h0010_1200, "Conflict Tag 1    ");

        // Test 7: Another Conflict Address with same index (0x00201204 -> Tag 0x000804, Index 0x20)
        check_decode(32'h0020_1204, 22'h000804, 6'h20, 4'h4, 2'b01, 2'b00, 32'h0020_1200, "Conflict Tag 2    ");

        // Test 8: Complex Arbitrary Pattern (0x12345678)
        // Tag: 32'h12345678 >> 10 = 22'h048D15
        // Index: (32'h12345678 >> 4) & 6'h3F = 6'h27 (39)
        // Block Offset: 4'h8, Word: 2'b10 (word 2), Byte: 2'b00
        // Block Addr: 32'h12345670
        check_decode(32'h1234_5678, 22'h048D15, 6'h27, 4'h8, 2'b10, 2'b00, 32'h1234_5670, "Arbitrary Pattern ");

        // Test 9-72: Sweep all 64 indices (index 0 to 63)
        for (idx = 0; idx < 64; idx = idx + 1) begin
            sweep_addr = (32'h00A5A5 << 10) | (idx << 4) | (idx & 4'hF);
            check_decode(sweep_addr,
                         22'h00A5A5,
                         idx[5:0],
                         idx[3:0],
                         idx[3:2],
                         idx[1:0],
                         {sweep_addr[31:4], 4'b0000},
                         "Index Sweep       ");
        end

        $display("===============================================================================");
        $display("ADDRESS DECODER RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("===============================================================================");

        if (fail_count == 0)
            $display(">>> ALL ADDRESS DECODER TESTS PASSED <<<");
        else
            $display(">>> VERIFICATION FAILED WITH %0d ERRORS <<<", fail_count);

        $finish;
    end

endmodule
