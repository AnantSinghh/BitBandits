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

// -----------------------------------------------------------------------------
// TEST 5: Conflict Miss Test
// - Generate addresses with identical index (e.g. Index 0) but different tags:
//   Addr A: 0x00000000 (Tag 0, Index 0)
//   Addr B: 0x00000400 (Tag 1, Index 0)
//   Addr C: 0x00000800 (Tag 2, Index 0)
// - Verify each access evicts and replaces the resident block.
// - Re-access evicted addresses to prove conflict miss and replacement.
// -----------------------------------------------------------------------------
task automatic run_test_conflict_miss();
    logic [31:0] addr_a, addr_b, addr_c;
    logic [31:0] rdata;
    logic        hit;
    logic        miss;
    int          lat;
    logic [31:0] exp_data;

    $display("\n===============================================================================");
    $display("   [TEST 5] CONFLICT MISS & LINE REPLACEMENT TEST                              ");
    $display("===============================================================================");

    addr_a = 32'h0000_0000; // Tag 0x000000, Index 0, Offset 0
    addr_b = 32'h0000_0400; // Tag 0x000001, Index 0, Offset 0
    addr_c = 32'h0000_0800; // Tag 0x000002, Index 0, Offset 0

    // Step 1: Initial cold load of Addr A into Index 0
    total_tests++;
    exp_data = ref_mem_word(addr_a);
    cpu_read(addr_a, rdata, hit, miss, lat);
    if (miss && !hit && (rdata === exp_data)) begin
        passed_tests++;
        $display("   [PASS] Step 1: Load Addr A (0x%08h) -> Compulsory Miss, Line 0 allocated Tag 0x000000", addr_a);
    end else begin
        failed_tests++;
        $error("   [FAIL] Step 1: Expected Compulsory Miss for Addr A (0x%08h)!", addr_a);
    end

    // Verify Addr A hits when re-accessed immediately (resident in Line 0)
    total_tests++;
    cpu_read(addr_a, rdata, hit, miss, lat);
    if (hit && !miss && (rdata === exp_data)) begin
        passed_tests++;
        $display("   [PASS] Step 2: Re-access Addr A (0x%08h) -> Hit confirmed (Tag 0x000000 resident)", addr_a);
    end else begin
        failed_tests++;
        $error("   [FAIL] Step 2: Expected Hit for Addr A (0x%08h)!", addr_a);
    end

    // Step 3: Access Addr B -> Same index 0, Tag 1 != Tag 0 -> Conflict Miss & Replacement
    total_tests++;
    exp_data = ref_mem_word(addr_b);
    cpu_read(addr_b, rdata, hit, miss, lat);
    if (miss && !hit && (rdata === exp_data)) begin
        passed_tests++;
        $display("   [PASS] Step 3: Load Addr B (0x%08h) -> Conflict Miss confirmed! Evicted Tag 0x0, installed Tag 0x1", addr_b);
    end else begin
        failed_tests++;
        $error("   [FAIL] Step 3: Expected Conflict Miss for Addr B (0x%08h)!", addr_b);
    end

    // Step 4: Access Addr C -> Same index 0, Tag 2 != Tag 1 -> Conflict Miss & Replacement
    total_tests++;
    exp_data = ref_mem_word(addr_c);
    cpu_read(addr_c, rdata, hit, miss, lat);
    if (miss && !hit && (rdata === exp_data)) begin
        passed_tests++;
        $display("   [PASS] Step 4: Load Addr C (0x%08h) -> Conflict Miss confirmed! Evicted Tag 0x1, installed Tag 0x2", addr_c);
    end else begin
        failed_tests++;
        $error("   [FAIL] Step 4: Expected Conflict Miss for Addr C (0x%08h)!", addr_c);
    end

    // Step 5: Re-access Addr A -> Must MISS because it was evicted by B and C!
    total_tests++;
    exp_data = ref_mem_word(addr_a);
    cpu_read(addr_a, rdata, hit, miss, lat);
    if (miss && !hit && (rdata === exp_data)) begin
        passed_tests++;
        $display("   [PASS] Step 5: Re-access evicted Addr A -> Miss verified! Proves replacement & thrashing", addr_a);
    end else begin
        failed_tests++;
        $error("   [FAIL] Step 5: Expected Miss for evicted Addr A! Got Hit=%b, Miss=%b", hit, miss);
    end

    // Step 6: Access Word 1 of Addr A (0x00000004) -> Must HIT (proves Addr A is now newly resident)
    total_tests++;
    exp_data = ref_mem_word(32'h0000_0004);
    cpu_read(32'h0000_0004, rdata, hit, miss, lat);
    if (hit && !miss && (rdata === exp_data)) begin
        passed_tests++;
        $display("   [PASS] Step 6: Access Word 1 of re-fetched block -> Spatial Hit confirmed!");
    end else begin
        failed_tests++;
        $error("   [FAIL] Step 6: Expected Spatial Hit for Word 1!");
    end

    // Subtest 5B: Additional conflict test on Line 45 (Index = 6'd45 = 0x2D)
    $display("\n   --- Subtest 5B: Conflict Replacement on Line 45 (0x2D) ---");
    begin
        logic [31:0] conf_x, conf_y;
        conf_x = 32'h0000_02D0; // Tag 0x000000, Index 45 (0x2D)
        conf_y = 32'h0000_06D0; // Tag 0x000001, Index 45 (0x2D)

        // Access X
        total_tests++;
        exp_data = ref_mem_word(conf_x);
        cpu_read(conf_x, rdata, hit, miss, lat);
        if (miss && !hit && (rdata === exp_data)) passed_tests++;
        else failed_tests++;

        // Access Y (causes conflict miss and replaces X)
        total_tests++;
        exp_data = ref_mem_word(conf_y);
        cpu_read(conf_y, rdata, hit, miss, lat);
        if (miss && !hit && (rdata === exp_data)) begin
            passed_tests++;
            $display("   [PASS] Conflict Miss confirmed on Line 45: Addr=0x%08h evicted Addr=0x%08h", conf_y, conf_x);
        end else begin
            failed_tests++;
            $error("   [FAIL] Conflict Miss on Line 45 failed!");
        end
    end
endtask

