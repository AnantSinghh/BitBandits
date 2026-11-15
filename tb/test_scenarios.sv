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

// -----------------------------------------------------------------------------
// TEST 2: Temporal Locality Test
// - Access the same address repeatedly.
// - Verify first access misses (compulsory).
// - Verify subsequent accesses hit (zero memory refill, 2-cycle latency).
// -----------------------------------------------------------------------------
task automatic run_test_temporal_locality();
    logic [31:0] test_addr;
    logic [31:0] rdata;
    logic        hit;
    logic        miss;
    int          lat;
    logic [31:0] exp_data;
    const int    NUM_REPEATS = 5;

    $display("\n===============================================================================");
    $display("   [TEST 2] TEMPORAL LOCALITY TEST (Repeated Access to Same Address)           ");
    $display("===============================================================================");

    test_addr = 32'h0000_2004; // Tag = 0x000008, Index = 0x00 (Line 0), Word = 1
    exp_data  = ref_mem_word(test_addr);

    for (int rep = 1; rep <= NUM_REPEATS; rep++) begin
        total_tests++;
        cpu_read(test_addr, rdata, hit, miss, lat);

        if (rep == 1) begin
            // First access must miss
            if (miss && !hit && (rdata === exp_data)) begin
                passed_tests++;
                $display("   [PASS] Access %0d (Initial) : Miss confirmed | Latency = %0d cyc, Data = 0x%08h",
                         rep, lat, rdata);
            end else begin
                failed_tests++;
                $error("   [FAIL] Access %0d (Initial) : Expected Miss, Got Hit=%b, Miss=%b, Data=0x%08h",
                       rep, hit, miss, rdata);
            end
        end else begin
            // Subsequent accesses must hit
            if (hit && !miss && (rdata === exp_data) && (lat == 2)) begin
                passed_tests++;
                $display("   [PASS] Access %0d (Repeated): Hit confirmed  | Latency = %0d cyc, Data = 0x%08h",
                         rep, lat, rdata);
            end else begin
                failed_tests++;
                $error("   [FAIL] Access %0d (Repeated): Expected Hit with 2-cyc latency! Got Hit=%b, Miss=%b, Lat=%0d, Data=0x%08h",
                       rep, hit, miss, lat, rdata);
            end
        end
    end
endtask

// -----------------------------------------------------------------------------
// TEST 3: Spatial Locality Test
// - Access four words in the same 16-byte block.
// - Verify only the first access causes a miss.
// - Verify all four returned words are correct.
// -----------------------------------------------------------------------------
task automatic run_test_spatial_locality();
    logic [31:0] base_block_addr;
    logic [31:0] word_addr;
    logic [31:0] rdata;
    logic        hit;
    logic        miss;
    int          lat;
    logic [31:0] exp_data;

    $display("\n===============================================================================");
    $display("   [TEST 3] SPATIAL LOCALITY TEST (Access 4 Words in 16-Byte Block)            ");
    $display("===============================================================================");

    // Block 1: Access words sequentially: Word 0 -> 1 -> 2 -> 3
    base_block_addr = 32'h0000_5A00;
    $display("   --- Subtest 3A: Sequential Word In-Block Order (0 -> 1 -> 2 -> 3) ---");
    for (int w = 0; w < 4; w++) begin
        word_addr = base_block_addr + (w * 4);
        exp_data  = ref_mem_word(word_addr);
        total_tests++;

        cpu_read(word_addr, rdata, hit, miss, lat);

        if (w == 0) begin
            // Word 0 must miss (fetches block)
            if (miss && !hit && (rdata === exp_data)) begin
                passed_tests++;
                $display("   [PASS] Word %0d (Addr=0x%08h): Compulsory Miss | Latency = %0d cyc, Data = 0x%08h",
                         w, word_addr, lat, rdata);
            end else begin
                failed_tests++;
                $error("   [FAIL] Word %0d (Addr=0x%08h): Expected Miss! Got Hit=%b, Miss=%b, Data=0x%08h",
                       w, word_addr, hit, miss, rdata);
            end
        end else begin
            // Words 1, 2, 3 must hit due to spatial locality
            if (hit && !miss && (rdata === exp_data) && (lat == 2)) begin
                passed_tests++;
                $display("   [PASS] Word %0d (Addr=0x%08h): Spatial Hit     | Latency = %0d cyc, Data = 0x%08h",
                         w, word_addr, lat, rdata);
            end else begin
                failed_tests++;
                $error("   [FAIL] Word %0d (Addr=0x%08h): Expected Spatial Hit! Got Hit=%b, Miss=%b, Lat=%0d, Data=0x%08h",
                       w, word_addr, hit, miss, lat, rdata);
            end
        end
    end

    // Block 2: Access words out-of-order: Word 2 -> Word 0 -> Word 3 -> Word 1
    base_block_addr = 32'h0000_6B00;
    $display("\n   --- Subtest 3B: Non-sequential Word In-Block Order (2 -> 0 -> 3 -> 1) ---");
    begin
        int word_order[4] = '{2, 0, 3, 1};
        for (int step = 0; step < 4; step++) begin
            int w = word_order[step];
            word_addr = base_block_addr + (w * 4);
            exp_data  = ref_mem_word(word_addr);
            total_tests++;

            cpu_read(word_addr, rdata, hit, miss, lat);

            if (step == 0) begin
                if (miss && !hit && (rdata === exp_data)) begin
                    passed_tests++;
                    $display("   [PASS] Step %0d: Word %0d (Addr=0x%08h): Compulsory Miss | Latency = %0d cyc, Data = 0x%08h",
                             step+1, w, word_addr, lat, rdata);
                end else begin
                    failed_tests++;
                    $error("   [FAIL] Step %0d: Word %0d (Addr=0x%08h): Expected Miss! Got Hit=%b, Miss=%b, Data=0x%08h",
                           step+1, w, word_addr, hit, miss, rdata);
                end
            end else begin
                if (hit && !miss && (rdata === exp_data) && (lat == 2)) begin
                    passed_tests++;
                    $display("   [PASS] Step %0d: Word %0d (Addr=0x%08h): Spatial Hit     | Latency = %0d cyc, Data = 0x%08h",
                             step+1, w, word_addr, lat, rdata);
                end else begin
                    failed_tests++;
                    $error("   [FAIL] Step %0d: Word %0d (Addr=0x%08h): Expected Spatial Hit! Got Hit=%b, Miss=%b, Lat=%0d, Data=0x%08h",
                           step+1, w, word_addr, hit, miss, lat, rdata);
                end
            end
        end
    end
endtask

