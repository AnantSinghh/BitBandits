// =============================================================================
// Testbench:   tb_cache_top_integration
// Designer:    Manas (Integration Lead, coordinated with Anant)
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Comprehensive system integration testbench verifying all seven
//              mandatory architectural features:
//              1. First access to an address produces a compulsory miss.
//              2. Second access to the same address produces a cache hit.
//              3. Access to another word in the same block produces a cache hit.
//              4. Different blocks mapping to the same index cause replacement (conflict miss).
//              5. Access after replacement produces the correct result.
//              6. Reset invalidates all cache entries (no false hits).
//              7. Requests are not lost while controller is busy (consecutive requests handled).
// =============================================================================

`timescale 1ns / 1ps

module tb_cache_top_integration;

    reg         clk;
    reg         rst;
    reg         cpu_req_valid;
    reg  [31:0] cpu_req_addr;
    wire        cpu_ready;
    wire        cpu_resp_valid;
    wire [31:0] cpu_resp_data;

    wire [2:0]  fsm_state;
    wire        cache_hit;
    wire        cache_miss;

    // Instantiate Top-Level Design
    cache_top #(
        .ADDR_WIDTH   (32),
        .DATA_WIDTH   (32),
        .BLOCK_WIDTH  (128),
        .TAG_WIDTH    (22),
        .INDEX_WIDTH  (6),
        .OFFSET_WIDTH (4),
        .NUM_LINES    (64),
        .MEM_LATENCY  (2)
    ) dut (
        .clk            (clk),
        .rst            (rst),
        .cpu_req_valid  (cpu_req_valid),
        .cpu_req_addr   (cpu_req_addr),
        .cpu_ready      (cpu_ready),
        .cpu_resp_valid (cpu_resp_valid),
        .cpu_resp_data  (cpu_resp_data),
        .fsm_state      (fsm_state),
        .cache_hit      (cache_hit),
        .cache_miss     (cache_miss)
    );

    // 100 MHz clock generation (10ns period)
    always #5 clk = ~clk;

    // Test tracking variables
    integer total_tests  = 0;
    integer passed_tests = 0;
    integer failed_tests = 0;

    reg saw_hit;
    reg saw_miss;

    // Monitor hit/miss flags dynamically during LOOKUP state
    always @(posedge clk) begin
        if (fsm_state == 3'b001) begin // LOOKUP state
            if (cache_hit)  saw_hit  <= 1'b1;
            if (cache_miss) saw_miss <= 1'b1;
        end
    end

    // Task to execute a CPU Read Transaction
    task cpu_read_transaction;
        input  [31:0] addr;
        output [31:0] data;
        output        hit_detected;
        output        miss_detected;
        begin
            // Clear monitoring flags
            saw_hit  = 1'b0;
            saw_miss = 1'b0;

            // Wait until cache controller is ready
            while (!cpu_ready) @(posedge clk);

            // Drive request on negative edge for clean setup
            @(negedge clk);
            cpu_req_valid = 1'b1;
            cpu_req_addr  = addr;
            @(negedge clk);
            cpu_req_valid = 1'b0;

            // Wait for response
            while (!cpu_resp_valid) @(posedge clk);

            data          = cpu_resp_data;
            hit_detected  = saw_hit;
            miss_detected = saw_miss;

            @(posedge clk); // Allow transition back to IDLE
        end
    endtask

    // Expected data calculation based on Anant's main_memory model:
    // w0 = {b_addr[31:4], 4'h0, 12'hA01};
    // w1 = {b_addr[31:4], 4'h4, 12'hB02};
    // w2 = {b_addr[31:4], 4'h8, 12'hC03};
    // w3 = {b_addr[31:4], 4'hC, 12'hD04};
    function [31:0] get_expected_word;
        input [31:0] addr;
        reg [1:0] w_sel;
        begin
            w_sel = addr[3:2];
            case (w_sel)
                2'b00: get_expected_word = {addr[31:4], 4'h0, 12'hA01};
                2'b01: get_expected_word = {addr[31:4], 4'h4, 12'hB02};
                2'b10: get_expected_word = {addr[31:4], 4'h8, 12'hC03};
                2'b11: get_expected_word = {addr[31:4], 4'hC, 12'hD04};
            endcase
        end
    endfunction

    reg [31:0] read_data;
    reg [31:0] exp_data;
    reg        hit_flag;
    reg        miss_flag;

    initial begin
        // Waveform generation setup
        $dumpfile("sim/cache_integration.vcd");
        $dumpvars(0, tb_cache_top_integration);

        $display("===============================================================================");
        $display("STARTING DIRECT-MAPPED CACHE CONTROLLER TOP-LEVEL INTEGRATION SUITE");
        $display("===============================================================================");

        clk           = 0;
        rst           = 1;
        cpu_req_valid = 0;
        cpu_req_addr  = 0;
        saw_hit       = 0;
        saw_miss      = 0;

        #25;
        @(negedge clk);
        rst = 0;
        #15;

        // ---------------------------------------------------------------------
        // TEST 1: First access to an address produces a compulsory miss
        // ---------------------------------------------------------------------
        total_tests = total_tests + 1;
        $display("\n[TEST 1] First access to address 0x0000_1204 (Cold / Compulsory Miss)");
        exp_data = get_expected_word(32'h0000_1204);
        cpu_read_transaction(32'h0000_1204, read_data, hit_flag, miss_flag);

        if (miss_flag && !hit_flag && (read_data === exp_data)) begin
            $display("         [PASS] Result: Compulsory Miss detected, Data = 0x%08h (Expected 0x%08h)", read_data, exp_data);
            passed_tests = passed_tests + 1;
        end else begin
            $display("         [FAIL] Test 1 failed! Miss=%b, Hit=%b, Data = 0x%08h, Expected = 0x%08h",
                     miss_flag, hit_flag, read_data, exp_data);
            failed_tests = failed_tests + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 2: Second access to the same address produces a cache hit
        // ---------------------------------------------------------------------
        total_tests = total_tests + 1;
        $display("\n[TEST 2] Second access to the exact same address 0x0000_1204 (Cache Hit)");
        cpu_read_transaction(32'h0000_1204, read_data, hit_flag, miss_flag);

        if (hit_flag && !miss_flag && (read_data === exp_data)) begin
            $display("         [PASS] Result: Cache Hit detected, Data = 0x%08h (Expected 0x%08h)", read_data, exp_data);
            passed_tests = passed_tests + 1;
        end else begin
            $display("         [FAIL] Test 2 failed! Hit=%b, Miss=%b, Data = 0x%08h, Expected = 0x%08h",
                     hit_flag, miss_flag, read_data, exp_data);
            failed_tests = failed_tests + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 3: Access to another word in the same block produces a hit (Spatial Locality)
        // ---------------------------------------------------------------------
        total_tests = total_tests + 1;
        $display("\n[TEST 3] Access to another word in same block: 0x0000_120C (Word 3)");
        exp_data = get_expected_word(32'h0000_120C);
        cpu_read_transaction(32'h0000_120C, read_data, hit_flag, miss_flag);

        if (hit_flag && !miss_flag && (read_data === exp_data)) begin
            $display("         [PASS] Result: Spatial Locality Hit, Data = 0x%08h (Expected 0x%08h)", read_data, exp_data);
            passed_tests = passed_tests + 1;
        end else begin
            $display("         [FAIL] Test 3 failed! Hit=%b, Miss=%b, Data = 0x%08h, Expected = 0x%08h",
                     hit_flag, miss_flag, read_data, exp_data);
            failed_tests = failed_tests + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 4: Different block mapping to same index causes replacement (Conflict Miss)
        // ---------------------------------------------------------------------
        // Address A: 0x0000_1204 -> Index = 0x20 (lines[32]), Tag = 0x000004
        // Address B: 0x0010_1204 -> Index = 0x20 (lines[32]), Tag = 0x000404 (Different Tag!)
        total_tests = total_tests + 1;
        $display("\n[TEST 4] Conflict access to address 0x0010_1204 (Same Index 0x20, Different Tag)");
        exp_data = get_expected_word(32'h0010_1204);
        cpu_read_transaction(32'h0010_1204, read_data, hit_flag, miss_flag);

        if (miss_flag && !hit_flag && (read_data === exp_data)) begin
            $display("         [PASS] Result: Conflict Miss & Line Replacement verified, Data = 0x%08h", read_data);
            passed_tests = passed_tests + 1;
        end else begin
            $display("         [FAIL] Test 4 failed! Miss=%b, Hit=%b, Data = 0x%08h, Expected = 0x%08h",
                     miss_flag, hit_flag, read_data, exp_data);
            failed_tests = failed_tests + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 5: Access original address A after replacement produces correct result (Miss & Refill)
        // ---------------------------------------------------------------------
        total_tests = total_tests + 1;
        $display("\n[TEST 5] Re-access Address A (0x0000_1204) after eviction");
        exp_data = get_expected_word(32'h0000_1204);
        cpu_read_transaction(32'h0000_1204, read_data, hit_flag, miss_flag);

        if (miss_flag && !hit_flag && (read_data === exp_data)) begin
            $display("         [PASS] Result: Correct re-fetch after replacement, Data = 0x%08h", read_data);
            passed_tests = passed_tests + 1;
        end else begin
            $display("         [FAIL] Test 5 failed! Miss=%b, Hit=%b, Data = 0x%08h, Expected = 0x%08h",
                     miss_flag, hit_flag, read_data, exp_data);
            failed_tests = failed_tests + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 6: Reset invalidates all cache entries (No stale / false hits)
        // ---------------------------------------------------------------------
        total_tests = total_tests + 1;
        $display("\n[TEST 6] Hardware Reset Invalidation Test");
        // Prior to reset, 0x0000_1204 is in cache and would hit.
        // Assert reset
        @(negedge clk);
        rst = 1;
        @(negedge clk);
        @(negedge clk);
        rst = 0;
        @(posedge clk);

        // Access 0x0000_1204 again: must produce a MISS because valid bits were cleared
        exp_data = get_expected_word(32'h0000_1204);
        cpu_read_transaction(32'h0000_1204, read_data, hit_flag, miss_flag);

        if (miss_flag && !hit_flag && (read_data === exp_data)) begin
            $display("         [PASS] Result: Reset verified: Entry was invalidated, produced MISS as required");
            passed_tests = passed_tests + 1;
        end else begin
            $display("         [FAIL] Test 6 failed! False hit occurred after reset! Hit=%b, Miss=%b", hit_flag, miss_flag);
            failed_tests = failed_tests + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 7: Requests are not lost while controller is busy (Backpressure & Multi-request)
        // ---------------------------------------------------------------------
        total_tests = total_tests + 1;
        $display("\n[TEST 7] Consecutive Requests & Backpressure Verification");
        begin : test7_block
            reg [31:0] d1, d2, d3;
            reg [31:0] exp1, exp2, exp3;
            reg busy_check_passed;
            busy_check_passed = 1'b1;

            exp1 = get_expected_word(32'h0000_5000);
            exp2 = get_expected_word(32'h0000_5004);
            exp3 = get_expected_word(32'h0000_6000);

            // Subtest 7A: Issue request 1 (cold miss)
            @(negedge clk);
            cpu_req_valid = 1'b1;
            cpu_req_addr  = 32'h0000_5000;
            @(negedge clk);
            cpu_req_valid = 1'b0;

            // Wait until FSM enters MEM_WAIT
            while (fsm_state !== 3'b011) @(posedge clk);

            // While controller is busy in MEM_WAIT, cpu_ready must be 0
            if (cpu_ready !== 1'b0) begin
                $display("         [FAIL] cpu_ready was not 0 while controller was busy in MEM_WAIT!");
                busy_check_passed = 1'b0;
            end else begin
                $display("         [PASS] Subtest 7A: cpu_ready is strictly 0 while controller is busy");
            end

            // Wait for response to first request
            while (!cpu_resp_valid) @(posedge clk);
            d1 = cpu_resp_data;
            @(posedge clk);

            // Subtest 7B: Immediately issue request 2 (hit in same block)
            cpu_read_transaction(32'h0000_5004, d2, hit_flag, miss_flag);

            // Subtest 7C: Immediately issue request 3 (different line)
            cpu_read_transaction(32'h0000_6000, d3, hit_flag, miss_flag);

            if (busy_check_passed && (d1 === exp1) && (d2 === exp2) && (d3 === exp3)) begin
                $display("         [PASS] Result: Backpressure and 3 consecutive transactions completed seamlessly without manual reset");
                passed_tests = passed_tests + 1;
            end else begin
                $display("         [FAIL] Test 7 consecutive transaction data mismatch!");
                failed_tests = failed_tests + 1;
            end
        end

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        $display("\n===============================================================================");
        $display("INTEGRATION VERIFICATION SUMMARY: %0d / %0d TESTS PASSED (Failed: %0d)",
                 passed_tests, total_tests, failed_tests);
        $display("===============================================================================");

        if (failed_tests == 0) begin
            $display(">>> ALL TOP-LEVEL INTEGRATION TESTS PASSED PERFECTLY! <<<");
        end else begin
            $display(">>> INTEGRATION ISSUES DETECTED - DEBUGGING REQUIRED <<<");
        end

        $finish;
    end

endmodule
