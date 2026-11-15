// =============================================================================
// File:        test_scenarios.sv
// Author:      Anant (Senior Hardware Verification Engineer)
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Modular test scenario implementations for cache verification.
//              Included within tb_cache_top to execute structured test sequences:
//              - TEST 1: Cold Cache Test
//              - TEST 2: Temporal Locality
//              - TEST 3: Spatial Locality
//              - TEST 4: Sequential Access
//              - TEST 5: Conflict Miss
//              - TEST 6: Random Access Workload
//              - TEST 7: Reset Behavior
//              - TEST 8: Consecutive Requests & Backpressure
// =============================================================================

// -----------------------------------------------------------------------------
// Baseline Test Scenario Framework
// -----------------------------------------------------------------------------
task automatic run_basic_sanity_check();
    logic [31:0] test_addr;
    logic [31:0] rdata;
    logic        hit;
    logic        miss;
    int          lat;
    logic [31:0] exp_data;

    $display("\n===============================================================================");
    $display("   [SANITY CHECK] Executing Basic Cache Initialization & Read Check           ");
    $display("===============================================================================");

    test_addr = 32'h0000_1000;
    exp_data  = ref_mem_word(test_addr);

    cpu_read(test_addr, rdata, hit, miss, lat);

    total_tests++;
    if (miss && !hit && (rdata === exp_data)) begin
        passed_tests++;
        $display("   [PASS] Sanity read successful: Addr=0x%08h -> Data=0x%08h (Miss detected, latency=%0d cyc)",
                 test_addr, rdata, lat);
    end else begin
        failed_tests++;
        $error("   [FAIL] Sanity read failed: Addr=0x%08h -> Got Data=0x%08h, Exp Data=0x%08h, Hit=%b, Miss=%b",
               test_addr, rdata, exp_data, hit, miss);
    end
endtask

// -----------------------------------------------------------------------------
// TEST 1: Cold Cache Test
// - Reset cache.
// - Access an address (and multiple test addresses across lines).
// - Verify first access is a miss (compulsory miss).
// - Verify returned data strictly matches main memory reference model.
// -----------------------------------------------------------------------------
task automatic run_test_cold_cache();
    logic [31:0] test_addrs [4];
    logic [31:0] rdata;
    logic        hit;
    logic        miss;
    int          lat;
    logic [31:0] exp_data;
    int          subtest_passed;

    $display("\n===============================================================================");
    $display("   [TEST 1] COLD CACHE TEST (Compulsory Miss Verification)                     ");
    $display("===============================================================================");

    // Step 1: Ensure cache is cleanly reset
    @(negedge clk);
    rst = 1'b1;
    @(negedge clk);
    @(negedge clk);
    rst = 1'b0;
    reset_ref_cache();
    @(posedge clk);
    #5;

    test_addrs[0] = 32'h0000_1204; // Index = 0x20 (Line 32), Tag = 0x000004, Offset = 0x4
    test_addrs[1] = 32'h0000_2408; // Index = 0x00 (Line 0),  Tag = 0x000009, Offset = 0x8
    test_addrs[2] = 32'h0000_360C; // Index = 0x20 (Line 32), Tag = 0x00000D, Offset = 0xC
    test_addrs[3] = 32'h0000_4800; // Index = 0x00 (Line 0),  Tag = 0x000012, Offset = 0x0

    for (int i = 0; i < 4; i++) begin
        total_tests++;
        exp_data = ref_mem_word(test_addrs[i]);

        $display("   [Subtest 1.%0d] Cold access to Address 0x%08h (Index=%0d, Word=%0d)",
                 i+1, test_addrs[i], test_addrs[i][9:4], test_addrs[i][3:2]);

        cpu_read(test_addrs[i], rdata, hit, miss, lat);

        if (miss && !hit && (rdata === exp_data)) begin
            passed_tests++;
            $display("         [PASS] Compulsory Miss confirmed | Data = 0x%08h (Expected 0x%08h), Latency = %0d cycles",
                     rdata, exp_data, lat);
        end else begin
            failed_tests++;
            $error("         [FAIL] Cold cache check failed! Addr=0x%08h, Hit=%b, Miss=%b, Got=0x%08h, Expected=0x%08h",
                   test_addrs[i], hit, miss, rdata, exp_data);
        end
    end
endtask

